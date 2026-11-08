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
import Security

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
            case .exarotonToken: return "exaroton.account"
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

    #if DEBUG
    /// 仅诊断用：列出本机 Keychain 里的业务账户名（**不读内容**），用于"数据丢了还能不能找回"的排查。
    static func debugKeychainAccounts() -> [String] {
        var result: [String] = []
        for provider in Provider.allCases {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: provider.legacyService,
                kSecReturnAttributes as String: true,
                kSecMatchLimit as String: kSecMatchLimitAll,
            ]
            var item: CFTypeRef?
            guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess else { continue }
            let items: [[String: Any]]
            if let array = item as? [[String: Any]] { items = array }
            else if let single = item as? [String: Any] { items = [single] }
            else { continue }
            result += items.compactMap { $0[kSecAttrAccount as String] as? String }
        }
        return result.sorted()
    }
    #endif

    // MARK: - 云端记录（整条记录，不只凭据）

    /// 写一条**整记录**到 iCloud 后端（`CloudRecords` 用；`.iCloud` 不可用时抛错）。
    static func writeCloudRecord(_ record: ServerStorageRecord) throws {
        let backend = try backend(for: .iCloud, config: configuration())
        try backend.write(record)
    }

    static func removeCloudRecord(id: UUID, provider: String) {
        if let backend = try? backend(for: .iCloud, config: configuration()) {
            try? backend.remove(id: id, provider: provider)
        }
    }

    /// 枚举 iCloud 后端里的全部记录（读不到时返回空——调用方据此"这次不同步"，不当成"云端没有"）。
    static func cloudRecords() -> [ServerStorageRecord] {
        guard let backend = try? backend(for: .iCloud, config: configuration()),
              let records = try? backend.records()
        else { return [] }
        return records
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

    /// 共享 Keychain 访问组（`iCloud` 档位用它；与应用默认组并存，老数据不受影响）。
    ///
    /// 命名约定：`<TeamID>.com.joker.OrzMC.shared` —— entitlements 里写成
    /// `$(AppIdentifierPrefix)com.joker.OrzMC.shared`，团队前缀由签名注入。
    static let sharedAccessGroupSuffix = "com.joker.OrzMC.shared"

    /// 从**签名**里拿共享访问组；没开启 Keychain Sharing 时返回 `nil`
    /// → `iCloud` 档位置灰，而不是"写进去但静默不同步"。
    static func sharedAccessGroup() -> String? {
        #if os(macOS)
        // macOS：直接读进程的 code signing entitlements。
        guard let task = SecTaskCreateFromSelf(nil),
              let groups = SecTaskCopyValueForEntitlement(
                  task, "keychain-access-groups" as CFString, nil
              ) as? [String]
        else { return nil }
        return groups.first { $0.hasSuffix(sharedAccessGroupSuffix) }
        #else
        // iOS：entitlements 不暴露给进程，改从**内嵌描述文件**取 TeamID 拼出候选组，
        // 再用一次"写探针 + 删探针"确认这个组真的能用（没开能力时会 errSecMissingEntitlement）。
        guard let team = embeddedTeamIdentifier() else { return nil }
        let candidate = "\(team).\(sharedAccessGroupSuffix)"
        return probeAccessGroup(candidate) ? candidate : nil
        #endif
    }

    #if os(iOS)
    /// 从 `embedded.mobileprovision`（CMS 签名的 plist）里取第一个 `TeamIdentifier`。
    private static func embeddedTeamIdentifier() -> String? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8)),
              start.lowerBound < end.upperBound
        else { return nil }
        let plist = data.subdata(in: start.lowerBound..<end.upperBound)
        guard let object = try? PropertyListSerialization.propertyList(from: plist, format: nil),
              let dict = object as? [String: Any],
              let teams = dict["TeamIdentifier"] as? [String]
        else { return nil }
        return teams.first
    }

    /// 用一次性探针项确认访问组可用（写完立刻删）。
    private static func probeAccessGroup(_ group: String) -> Bool {
        let service = "com.joker.OrzMC.sync.probe"
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "probe",
            kSecAttrAccessGroup as String: group,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data("1".utf8)
        add[kSecAttrSynchronizable as String] = true
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(add as CFDictionary, nil)
        SecItemDelete(base as CFDictionary)
        return status == errSecSuccess
    }
    #endif

    nonisolated(unsafe) private static let live: Configuration = {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OrzMC/records", isDirectory: true)
        // 安装内记录的密钥放在**本机** Keychain（不同步），与记录本身分离。
        let keyStore = ServerRecordKeychain(
            service: "com.joker.OrzMC.installation",
            synchronizable: false
        )
        // 只有签名里真的带共享访问组时才启用同步后端；否则保持"不支持"（界面置灰）。
        let group = sharedAccessGroup()
        #if DEBUG
        // 验收用：确认签名里到底有没有共享组（不含任何凭据信息）。
        FileHandle.standardError.write(Data(
            "storage: sharedAccessGroup=\(group ?? "nil") iCloud=\(group == nil ? "unavailable" : "available")\n".utf8
        ))
        #endif
        let iCloud: (any ServerRecordBackend)? = group.map { group in
            ServerRecordKeychain(service: "com.joker.OrzMC.sync", synchronizable: true, accessGroup: group)
        }
        return Configuration(
            installation: ServerRecordInstallation(directory: support, keychain: keyStore),
            iCloud: iCloud
        )
    }()
}
