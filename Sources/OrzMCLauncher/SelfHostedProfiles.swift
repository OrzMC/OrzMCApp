//
//  SelfHostedProfiles.swift
//  OrzMCLauncher
//

import Foundation

/// 一台**自建**（自己用 `orzmc` / docker 起的）服务器的连接信息。
///
/// 只存"怎么连上去看状态 / 发命令"需要的最少字段：
/// 游戏端口用于 Server List Ping（跟游戏里多人列表同一份数据），
/// RCON 端口 + 密码用于执行控制台命令（密码在 Keychain，不在这个结构里）。
public struct SelfHostedServerProfile: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: Int
    /// RCON 端口；`rconEnabled == false` 时不使用。
    public var rconPort: Int
    public var rconEnabled: Bool

    public init(
        id: UUID = UUID(),
        name: String = "",
        host: String = "",
        port: Int = 25565,
        rconPort: Int = 25575,
        rconEnabled: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.rconPort = rconPort
        self.rconEnabled = rconEnabled
    }

    public var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...65535).contains(port)
    }

    /// 展示用地址（默认端口时省略端口）。
    public var address: String {
        port == 25565 ? host : "\(host):\(port)"
    }

    /// 列表/标题上显示的名字：没填名字就用地址。
    public var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? host : trimmed
    }
}

/// 全部自建服务器档案 + 当前选中项。
public struct SelfHostedProfiles: Codable, Equatable, Sendable {
    public var servers: [SelfHostedServerProfile]
    public var selectedID: UUID?

    public init(servers: [SelfHostedServerProfile] = [], selectedID: UUID? = nil) {
        self.servers = servers
        self.selectedID = selectedID
    }

    public var selected: SelfHostedServerProfile? {
        guard let selectedID else { return servers.first }
        return servers.first { $0.id == selectedID } ?? servers.first
    }

    /// 选中一台（`nil` = 沿用当前/第一台）。
    public mutating func select(_ id: UUID?) {
        selectedID = id ?? servers.first?.id
    }

    /// 新增或替换（按 id 匹配），并选中它。
    public mutating func upsert(_ profile: SelfHostedServerProfile) {
        if let index = servers.firstIndex(where: { $0.id == profile.id }) {
            servers[index] = profile
        } else {
            servers.append(profile)
        }
        selectedID = profile.id
    }

    public mutating func remove(id: UUID) {
        servers.removeAll { $0.id == id }
        if selectedID == id { selectedID = servers.first?.id }
    }
}

/// 自建服务器档案的本地存储（`UserDefaults` 里一段 JSON）。
///
/// 迁移：早期版本只有"一台"服务器，存在 `orzmc.selfHosted.profile`（没有 `id` 字段）。
/// 第一次读到新格式时，把旧记录转成一台档案并删掉旧键——用户升级后不会看到"配置没了"。
public enum SelfHostedProfilesStore {
    public static let storageKey = "orzmc.selfHosted.profiles"
    public static let legacyKey = "orzmc.selfHosted.profile"

    public static func load(defaults: UserDefaults = .standard) -> SelfHostedProfiles {
        if let data = defaults.data(forKey: storageKey),
           let profiles = try? JSONDecoder().decode(SelfHostedProfiles.self, from: data) {
            return profiles
        }
        if let migrated = migrateLegacy(defaults: defaults) {
            save(migrated, defaults: defaults)
            defaults.removeObject(forKey: legacyKey)
            return migrated
        }
        return SelfHostedProfiles()
    }

    public static func save(_ profiles: SelfHostedProfiles, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(profiles) else { return }
        defaults.set(data, forKey: storageKey)
    }

    /// 旧格式（无 `id`）→ 一台档案。解析失败返回 `nil`（当作没配置）。
    static func migrateLegacy(defaults: UserDefaults) -> SelfHostedProfiles? {
        guard let data = defaults.data(forKey: legacyKey) else { return nil }
        struct Legacy: Decodable {
            var name: String?
            var host: String?
            var port: Int?
            var rconPort: Int?
            var rconEnabled: Bool?
        }
        guard let legacy = try? JSONDecoder().decode(Legacy.self, from: data) else { return nil }
        let profile = SelfHostedServerProfile(
            name: legacy.name ?? "",
            host: legacy.host ?? "",
            port: legacy.port ?? 25565,
            rconPort: legacy.rconPort ?? 25575,
            rconEnabled: legacy.rconEnabled ?? false
        )
        guard profile.isConfigured else { return nil }
        return SelfHostedProfiles(servers: [profile], selectedID: profile.id)
    }
}
