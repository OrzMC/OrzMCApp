//
//  KeychainStore.swift
//  OrzMCFoundation
//

import Foundation
import Security

/// 极简 Keychain 封装（**只存密码类短字符串**，不存配置）。
///
/// 为什么不用 `UserDefaults`：RCON 密码是明文凭据，`UserDefaults` 是 plist，
/// 备份/同步里都能直接看到。Keychain 是系统给"一条口令"准备的正确位置。
///
/// 语义：`service` 用一个固定前缀，`account` 是业务键（如 `selfhosted.rcon`）。
/// 读写都**不抛错**：拿不到就当没有（用户重新输入一次即可），免得因为钥匙串状态
/// 让整个界面弹错窗。
public enum KeychainStore {

    public static let defaultService = "com.joker.OrzMC.credentials"

    /// 存（覆盖）一条口令。
    @discardableResult
    public static func set(_ value: String, account: String, service: String = defaultService) -> Bool {
        guard let data = value.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        // 先删再写：`SecItemUpdate` 在"不存在"时也要单独处理，逻辑更绕。
        SecItemDelete(query as CFDictionary)
        guard !value.isEmpty else { return true }     // 空值 = 删除

        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }

    /// 读；没有就返回 `nil`。
    public static func get(account: String, service: String = defaultService) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 删。
    @discardableResult
    public static func remove(account: String, service: String = defaultService) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
