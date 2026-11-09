//
//  ServerRecordStore.swift
//  OrzMCFoundation
//
//  服务器资料（自建服务器 / exaroton 账号 / MCSManager 面板）的**存储作用域路由**。
//
//  设计口径见 `docs/server-storage.md`：每条资料由用户单独选择
//  「仅本次安装 / 保留在本机 / iCloud 同步」，三个档位对应三个后端：
//    · installation —— 文件 + 本机密钥（`ServerRecordInstallation`）
//    · device       —— 本机 Keychain（不参与 iCloud：`synchronizable = false`）
//    · iCloud       —— 同步 Keychain（`synchronizable = true`，需要共享访问组）
//
//  这一层只做三件事：**路由**（按 mode 找后端）、**迁移**（先写后验、再删源）、
//  **如实报错**（后端不可读 ≠ 没有记录）。它不认识任何具体供应商的字段。
//

import Foundation

public struct ServerRecordStore: Sendable {
    /// 后端装配。`iCloud` 为 `nil` 表示这台设备/这个签名组合暂时没有同步后端
    /// （例如没开 iCloud 钥匙串、或 macOS 端还没配共享访问组）—— 这时对它的读写要**报错**，
    /// 不能当成"空"。
    public struct Backends: Sendable {
        public var installation: any ServerRecordBackend
        public var device: any ServerRecordBackend
        public var iCloud: (any ServerRecordBackend)?

        public init(
            installation: any ServerRecordBackend,
            device: any ServerRecordBackend,
            iCloud: (any ServerRecordBackend)? = nil
        ) {
            self.installation = installation
            self.device = device
            self.iCloud = iCloud
        }
    }

    public enum Failure: Error, Equatable {
        /// 该档位在这台设备上不可用（没开 iCloud 钥匙串等）。
        case backendUnavailable(ServerRecordStorageMode)
        /// 想迁移的记录不在它声称的来源里。
        case sourceMissing
        /// 目标里已有一条同 id/同 provider 但内容不同的记录。
        case conflict
        /// 迁移成功写入但回读不一致（比如同步还没落地）。
        case verificationFailed
    }

    public let backends: Backends

    public init(backends: Backends) {
        self.backends = backends
    }

    // MARK: - 路由

    public func backend(for mode: ServerRecordStorageMode) throws -> any ServerRecordBackend {
        switch mode {
        case .installation: return backends.installation
        case .device: return backends.device
        case .iCloud:
            guard let iCloud = backends.iCloud else {
                throw Failure.backendUnavailable(.iCloud)
            }
            return iCloud
        }
    }

    public func record(
        id: UUID,
        provider: String,
        mode: ServerRecordStorageMode
    ) throws -> ServerStorageRecord? {
        try backend(for: mode).records()
            .first { $0.id == id && $0.provider == provider }
    }

    public func records(provider: String, mode: ServerRecordStorageMode) throws -> [ServerStorageRecord] {
        try backend(for: mode).records().filter { $0.provider == provider }
    }

    // MARK: - 写入与删除

    public func write(_ record: ServerStorageRecord, mode: ServerRecordStorageMode) throws {
        try backend(for: mode).write(record)
    }

    /// 删除**所有**后端里的同一条记录。
    ///
    /// 删除是最容易"删一半"的动作（本地删了、iCloud 没删 → 旧设备把记录复活）。
    /// 这里逐后端尝试，任何一个失败都会抛错，调用方据此提示"部分设备仍保留"。
    public func remove(id: UUID, provider: String) throws {
        var firstError: Error?
        for backend in allBackends() {
            do {
                try backend.remove(id: id, provider: provider)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError { throw firstError }
    }

    // MARK: - 迁移

    /// 把一条记录从 `source` 搬到 `target`：**先写目标 + 回读校验，再删来源**。
    ///
    /// 顺序不能反：先删后写，一旦写入失败用户的资料就没了。
    /// 如果目标里已有同 id 但内容不同的记录，直接报 `conflict`，不覆盖。
    public func move(
        id: UUID,
        provider: String,
        from source: ServerRecordStorageMode,
        to target: ServerRecordStorageMode
    ) throws {
        guard source != target else { return }
        let sourceBackend = try backend(for: source)
        let targetBackend = try backend(for: target)

        guard let record = try sourceBackend.records()
            .first(where: { $0.id == id && $0.provider == provider })
        else { throw Failure.sourceMissing }

        if let existing = try targetBackend.records()
            .first(where: { $0.id == id && $0.provider == provider }) {
            guard existing == record else { throw Failure.conflict }
            // 目标已经是这份内容：只需把来源清掉（例如上次迁移删源失败后重试）。
            try sourceBackend.remove(id: id, provider: provider)
            return
        }

        try targetBackend.write(record)
        guard try targetBackend.records().contains(record) else {
            throw Failure.verificationFailed
        }
        try sourceBackend.remove(id: id, provider: provider)
    }

    // MARK: - 内部

    private func allBackends() -> [any ServerRecordBackend] {
        var list: [any ServerRecordBackend] = [backends.installation, backends.device]
        if let iCloud = backends.iCloud { list.append(iCloud) }
        return list
    }
}
