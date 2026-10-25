//
//  MCSManagerPanel.swift
//  OrzMC
//
//  P2-7 第 4 步：MCSManager 面板的"身份"（地址 + 显示名）与凭据存储。
//  供应商抽象层在 `Sources/OrzMCRemoteHosting`，API 调用在 `OrzMC/MCSManagerAPI`（SwiftPM 依赖），
//  这一层只负责"app 怎么记一个面板、怎么拿它的 key"。
//

import Foundation
import OrzMCFoundation

/// 一个 MCSManager 面板（不含 key：key 在 Keychain 里，见 `MCSManagerCredentials`）。
struct MCSManagerPanel: Identifiable, Equatable, Codable, Sendable {
    let id: UUID
    var label: String
    /// 面板根地址（已规范化：有 scheme、无尾部斜杠）。
    var url: URL

    init(id: UUID = UUID(), label: String, url: URL) {
        self.id = id
        self.label = label
        self.url = url
    }

    /// 从用户输入解析面板地址。
    ///
    /// - 允许只填域名（`panel.example.com`）→ 补 `https://`（面板基本都在 HTTPS 后面）；
    /// - 去掉尾部斜杠（生成的请求路径本身以 `/api/...` 开头）；
    /// - 只接受 http/https，其它 scheme（`file://` 之类）直接拒绝。
    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let withScheme = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard var components = URLComponents(string: withScheme),
              let scheme = components.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = components.host, !host.isEmpty
        else { return nil }

        components.scheme = scheme
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        return components.url
    }

    /// 用户输入校验：地址能解析就返回规范化后的面板（显示名留空时用 host）。
    static func make(id: UUID = UUID(), label: String, rawURL: String) -> MCSManagerPanel? {
        guard let url = normalizedURL(from: rawURL) else { return nil }
        let trimmedLabel = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return MCSManagerPanel(
            id: id,
            label: trimmedLabel.isEmpty ? (url.host ?? url.absoluteString) : trimmedLabel,
            url: url
        )
    }
}

/// 面板列表 + API Key 的**存取接口**（真实实现走 UserDefaults + Keychain；单测用内存实现）。
protocol MCSManagerCredentialStore: AnyObject, Sendable {
    func panels() -> [MCSManagerPanel]
    func savePanels(_ panels: [MCSManagerPanel])
    func apiKey(for id: UUID) -> String?
    func saveAPIKey(_ apiKey: String, for id: UUID)
    func removeAPIKey(for id: UUID)
}

/// 默认实现：面板配置进 `UserDefaults`，API Key 进 `Keychain`。
final class KeychainCredentialStore: MCSManagerCredentialStore {
    func panels() -> [MCSManagerPanel] { MCSManagerCredentials.panels() }
    func savePanels(_ panels: [MCSManagerPanel]) { MCSManagerCredentials.save(panels) }
    func apiKey(for id: UUID) -> String? { MCSManagerCredentials.apiKey(for: id) }
    func saveAPIKey(_ apiKey: String, for id: UUID) { MCSManagerCredentials.saveAPIKey(apiKey, for: id) }
    func removeAPIKey(for id: UUID) { MCSManagerCredentials.removeAPIKey(for: id) }
}

/// 面板列表 + API Key 的存储。
///
/// - 面板本身（显示名 / 地址）不是秘密 → `UserDefaults`；
/// - API Key 与账号密码同权 → **Keychain**（`KeychainStore`，按面板 id 分开）。
enum MCSManagerCredentials {

    static let panelsKey = "MCSM_PANELS"
    static let keychainAccountPrefix = "mcsm.panel."

    // MARK: - 面板列表

    static func panels(defaults: UserDefaults = .standard) -> [MCSManagerPanel] {
        guard let data = defaults.data(forKey: panelsKey),
              let panels = try? JSONDecoder().decode([MCSManagerPanel].self, from: data)
        else { return [] }
        return panels
    }

    static func save(_ panels: [MCSManagerPanel], defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(panels) else { return }
        defaults.set(data, forKey: panelsKey)
    }

    // MARK: - API Key（Keychain）

    static func apiKey(for id: UUID) -> String? {
        #if DEBUG
        // 与 exaroton 的 `ORZMC_DEMO_TOKEN` 同理：模拟器/无 GUI 会话里 Keychain 不可写，
        // 界面验收用环境变量直接注入。发布构建里没有这条路径。
        if let demo = ProcessInfo.processInfo.environment["ORZMC_DEMO_MCSM_APIKEY"], !demo.isEmpty {
            return demo
        }
        #endif
        guard let key = KeychainStore.get(account: keychainAccountPrefix + id.uuidString) else {
            return nil
        }
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func saveAPIKey(_ apiKey: String, for id: UUID) {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            KeychainStore.remove(account: keychainAccountPrefix + id.uuidString)
        } else {
            KeychainStore.set(trimmed, account: keychainAccountPrefix + id.uuidString)
        }
    }

    static func removeAPIKey(for id: UUID) {
        KeychainStore.remove(account: keychainAccountPrefix + id.uuidString)
    }
}
