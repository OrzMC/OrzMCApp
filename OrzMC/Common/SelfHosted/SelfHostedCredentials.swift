//
//  SelfHostedCredentials.swift
//  OrzMC
//

import Foundation
import OrzMCFoundation
import OrzMCLauncher

/// 自建服务器的 **RCON 密码**存取（Keychain，按档案 id 分开）。
///
/// 为什么不放在 `SelfHostedServerProfile` 里：那个类型在 `OrzMCLauncher`（平台无关层），
/// 只描述"怎么连"，不碰任何凭据存储；密码属于应用侧的安全存储。
enum SelfHostedCredentials {

    /// 旧版本只有一台服务器，密码存在这个固定账户里。
    static let legacyAccount = "selfhosted.rcon.password"

    private static func account(for id: UUID) -> String {
        "selfhosted.rcon.\(id.uuidString)"
    }

    static func password(for id: UUID) -> String? {
        #if DEBUG
        // **仅调试构建**的验收通道：本地联调时用假 SLP/RCON 服务端（`scripts/test-servers/`），
        // 真机上的 Keychain 在无 GUI 会话里写不进去，于是允许用环境变量临时提供密码。
        // 发布构建里这段代码不存在。
        if let demo = ProcessInfo.processInfo.environment["ORZMC_DEMO_RCON_PASSWORD"], !demo.isEmpty {
            return demo
        }
        #endif
        return KeychainStore.get(account: account(for: id))
    }

    static func save(_ password: String, for id: UUID) {
        KeychainStore.set(password, account: account(for: id))
    }

    static func remove(for id: UUID) {
        KeychainStore.remove(account: account(for: id))
    }

    /// 把旧版本的单一密码迁到第一台档案上（迁移只做一次：旧账户随后删除）。
    static func migrateLegacyPasswordIfNeeded(to id: UUID) {
        guard KeychainStore.get(account: account(for: id)) == nil,
              let legacy = KeychainStore.get(account: legacyAccount),
              !legacy.isEmpty
        else { return }
        KeychainStore.set(legacy, account: account(for: id))
        KeychainStore.remove(account: legacyAccount)
    }
}
