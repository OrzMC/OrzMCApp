//
//  ServerSecretsStore.swift
//  OrzMC
//
//  服务器资料里的**凭据**（自建 RCON 密码 / Exaroton Token / MCSManager API Key）按
//  「保存方式」路由到对应后端。设计见 `docs/server-storage-design-2026-11-04.md`。
//
//  三档：
//    · `.device`（默认，保留在本机）—— **沿用旧 Keychain 的 service/account 命名**，
//      老用户零迁移、升级后照旧能读到；这一档不参与 iCloud 同步。
//    · `.installation`（仅本次安装）—— 加密文件 + 本机密钥（`ServerRecordInstallation`）。
//    · `.iCloud`（同步）—— 同步 Keychain（`ServerRecordKeychain(synchronizable: true)`）。
//
//  两个约定（与 P1 的 `ServerRecordStore` 一致）：
//    1. **不可读 ≠ 空**：读失败要抛错，调用方据此提示，而不是当成"用户没设过"。
//    2. **切换档位先写后删**：`move(from:to:)` 写目标 → 回读校验 → 删来源；失败保留原记录。
//

import Foundation
import OrzMCFoundation

enum ServerSecretsStore {

    /// 凭据所属的业务域。`recordProvider` 写进记录（便于排查与迁移），`legacyAccount` 是
    /// 老版本 Keychain 的账户名格式 —— **不要改**，改了老用户的凭据就读不到了。
    enum Provider: String, CaseIterable {
        case selfHostedRCON
        case exarotonToken
        case mcsmAPIKey

        var recordProvider: String {
            switch self {
            case .selfHostedRCON: return "selfhosted.rcon"
            case .exarotonToken: return "exaroton.token"
            case .mcsmAPIKey: return "mcsm.panel"
            }
        }

        func legacyAccount(id: UUID) -> String { "\(recordProvider).\(id.uuidString)" }

        /// 老版本用的 Keychain service（两处不同：exaroton 用 bundle id，其余用一个固定串）。
        var legacyService: String {
            switch self {
            case .exarotonToken: return Bundle.main.bundleIdentifier ?? "OrzMC"
            case .selfHostedRCON, .mcsmAPIKey: return KeychainStore.defaultService
            }
        }
    }

    enum Failure: LocalizedError, Equatable {
        /// 该档位的后端不可用（没开 iCloud 钥匙串 / 签名里没有共享访问组等）。
        case unavailable(ServerRecordStorageMode)
        case writeFailed
        case conflict
        case verificationFailed
        case sourceMissing

        var errorDescription: String? {
            switch self {
            case .unavailable:
                return String(localized: "This storage option is not available on this device.")
            case .writeFailed:
                return String(localized: "Could not save to the selected storage option.")
            case .conflict:
                return String(localized: "Another copy of this item already exists in the target storage.")
            case .verificationFailed:
                return String(localized: "The item could not be verified after saving.")
            case .sourceMissing:
                return String(localized: "The item was not found in its current storage.")
            }
        }
    }

    /// 运行配置（单测可注入内存后端）。
    struct Configuration: @unchecked Sendable {
        /// 仅本次安装：加密文件 + 本机密钥。
        var installation: any ServerRecordBackend
        /// `nil` = 这台设备暂时没有同步后端（界面要把 `.iCloud` 置灰）。
        var iCloud: (any ServerRecordBackend)?
    }

    // MARK: - 对外接口

    static func secret(id: UUID, provider: Provider, mode: ServerRecordStorageMode) -> String? {
        let config = configuration()
        // `.device` 直接读老 Keychain（不走记录格式），老数据保持可读。
        if mode == .device {
            return legacySecret(id: id, provider: provider, config: config)
        }
        if let text = try? recordSecret(id: id, provider: provider, mode: mode, config: config) {
            return text
        }
        // 还没迁移过：退回读老 Keychain，避免"切档位=看不见密码"。
        return legacySecret(id: id, provider: provider, config: config)
    }

    @discardableResult
    static func save(
        _ secret: String,
        id: UUID,
        provider: Provider,
        mode: ServerRecordStorageMode
    ) -> Bool {
        let config = configuration()
        guard !secret.isEmpty else {
            remove(id: id, provider: provider, config: config)
            return true
        }
        do {
            switch mode {
            case .device:
                return KeychainStore.set(secret, account: provider.legacyAccount(id: id), service: provider.legacyService)
            case .installation, .iCloud:
                let backend = try backend(for: mode, config: config)
                try backend.write(Self.record(secret: secret, id: id, provider: provider))
                return true
            }
        } catch {
            return false
        }
    }

    static func remove(id: UUID, provider: Provider) {
        remove(id: id, provider: provider, config: configuration())
    }

    /// 切换保存方式：先写到目标并回读，再删来源。任何一步失败都保留来源。
    static func move(
        id: UUID,
        provider: Provider,
        from source: ServerRecordStorageMode,
        to target: ServerRecordStorageMode
    ) throws {
        guard source != target else { return }
        guard let secret = secret(id: id, provider: provider, mode: source) else {
            throw Failure.sourceMissing
        }
        let config = configuration()
        if target == .device {
            guard KeychainStore.set(secret, account: provider.legacyAccount(id: id), service: provider.legacyService)
            else { throw Failure.writeFailed }
        } else {
            let backend = try backend(for: target, config: config)
            try backend.write(Self.record(secret: secret, id: id, provider: provider))
            guard try backend.records().contains(Self.record(secret: secret, id: id, provider: provider)) else {
                throw Failure.verificationFailed
            }
        }
        // 目标写成功后才清理来源。
        if source == .device {
            KeychainStore.set("", account: provider.legacyAccount(id: id), service: provider.legacyService)
        } else if let backend = try? backend(for: source, config: config) {
            try? backend.remove(id: id, provider: provider.recordProvider)
        }
    }

    /// 这台设备是否支持某个档位（界面用来置灰）。
    static func isAvailable(_ mode: ServerRecordStorageMode) -> Bool {
        switch mode {
        case .installation, .device: return true
        case .iCloud: return configuration().iCloud != nil
        }
    }

    // MARK: - 内部

    static func record(secret: String, id: UUID, provider: Provider) -> ServerStorageRecord {
        ServerStorageRecord(id: id, provider: provider.recordProvider, payload: Data(secret.utf8))
    }

    private static func legacySecret(id: UUID, provider: Provider, config: Configuration) -> String? {
        KeychainStore.get(account: provider.legacyAccount(id: id), service: provider.legacyService)
    }

    private static func recordSecret(
        id: UUID,
        provider: Provider,
        mode: ServerRecordStorageMode,
        config: Configuration
    ) throws -> String? {
        let backend = try backend(for: mode, config: config)
        guard let record = try backend.records()
            .first(where: { $0.id == id && $0.provider == provider.recordProvider })
        else { return nil }
        return String(decoding: record.payload, as: UTF8.self)
    }

    private static func remove(id: UUID, provider: Provider, config: Configuration) {
        KeychainStore.set("", account: provider.legacyAccount(id: id), service: provider.legacyService)
        for mode in [ServerRecordStorageMode.installation, .iCloud] {
            if let backend = try? backend(for: mode, config: config) {
                try? backend.remove(id: id, provider: provider.recordProvider)
            }
        }
    }

    /// `.device` 没有独立后端对象：它就是要保持现状的老 Keychain，由上面的分支直接读写。
    private static func backend(
        for mode: ServerRecordStorageMode,
        config: Configuration
    ) throws -> any ServerRecordBackend {
        switch mode {
        case .installation: return config.installation
        case .iCloud:
            guard let iCloud = config.iCloud else { throw Failure.unavailable(.iCloud) }
            return iCloud
        case .device:
            throw Failure.unavailable(.device)
        }
    }

    // MARK: - 默认装配

    /// 三档默认装配。iOS/macOS 的存储目录不同，但都在应用支持目录下。
    /// 单测通过它注入内存后端（只在主线程/测试里写）。
    nonisolated(unsafe) static var injected: Configuration?

    private static func configuration() -> Configuration {
        #if DEBUG
        if let injected { return injected }
        #endif
        return live
    }

    nonisolated(unsafe) private static let live: Configuration = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OrzMC/records", isDirectory: true)
        // 安装内记录的密钥放在**本机** Keychain（不同步），与记录本身分离。
        let keyStore = ServerRecordKeychain(
            service: "com.joker.OrzMC.installation",
            synchronizable: false
        )
        return Configuration(
            installation: ServerRecordInstallation(directory: support, keychain: keyStore),
            // P4 之前 iCloud 后端一律不可用：没有共享访问组时强行写会静默不同步，
            // 界面会因此谎报"已同步"。这里先明确"不支持"。
            iCloud: nil
        )
    }()
}
