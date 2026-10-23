//
//  SelfHostedServerProfile.swift
//  OrzMC
//

import Foundation
import OrzMCFoundation

/// 一台**自建**（自己用 `orzmc` / docker 起的）服务器的连接信息。
///
/// 只存"怎么连上去看状态 / 发命令"需要的最少字段：
/// 游戏端口用于 Server List Ping（跟游戏里多人列表同一份数据），
/// RCON 端口 + 密码用于执行控制台命令。
///
/// 密码存 **Keychain**（见 `KeychainStore`），其余字段存 `UserDefaults`。
struct SelfHostedServerProfile: Codable, Equatable, Sendable {
    var name: String = ""
    var host: String = ""
    var port: Int = 25565
    /// RCON 端口；`0` = 没有开启 RCON（此时不显示控制台）。
    var rconPort: Int = 25575
    var rconEnabled: Bool = false

    var isConfigured: Bool {
        !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (1...65535).contains(port)
    }

    /// 展示用地址（`host:port`，默认端口时省略）。
    var address: String {
        port == 25565 ? host : "\(host):\(port)"
    }

    // MARK: 本地存储

    private static let defaultsKey = "orzmc.selfHosted.profile"
    private static let rconAccount = "selfhosted.rcon.password"

    static func load(defaults: UserDefaults = .standard) -> SelfHostedServerProfile {
        guard let data = defaults.data(forKey: defaultsKey),
              let profile = try? JSONDecoder().decode(SelfHostedServerProfile.self, from: data)
        else { return SelfHostedServerProfile() }
        return profile
    }

    func save(defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    static func rconPassword() -> String? {
        KeychainStore.get(account: rconAccount)
    }

    static func saveRCONPassword(_ password: String) {
        KeychainStore.set(password, account: rconAccount)
    }
}
