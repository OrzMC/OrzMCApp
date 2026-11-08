//
//  StorageMaintenance.swift
//  OrzMC
//
//  「清除本机资料」：把**卸载也不会自动删掉**的东西清干净。
//
//  为什么需要它（macOS 特有）：把 app 拖进废纸篓**不会**删 `~/Library/Application Support`，
//  也不会删钥匙串项；用户以为删了就没了，其实 RCON 密码 / Token / 安装内记录都还在。
//  所以给一个显式出口，并明确告诉用户**哪些会删、哪些不会**：
//
//    会删：安装内记录（加密文件）+ 本机 Keychain 凭据（RCON 密码 / Token / API Key）+ 安装密钥
//    不会删：iCloud 同步项（删了会影响其它设备，必须在各自的记录里改保存方式/删除）
//            以及窗口布局等应用偏好
//

import Foundation
import OrzMCFoundation
import Security

enum StorageMaintenance {
    struct Report: Equatable {
        var removedRecords: Int
        var removedKeychainItems: Int
        var failed: [String]
    }

    enum Failure: LocalizedError {
        case underlying(String)

        var errorDescription: String? {
            switch self {
            case .underlying(let message): return message
            }
        }
    }

    /// 安装内记录目录（与 `ServerSecretsStore` 的 live 配置一致）。
    static var installationDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OrzMC/records", isDirectory: true)
    }

    /// 本机凭据用到的 Keychain service（三处老命名 + 安装密钥）。
    static var localKeychainServices: [String] {
        var services = [
            KeychainStore.defaultService,                       // 自建 RCON 密码 / MCSM API Key
            Bundle.main.bundleIdentifier ?? "OrzMC",            // Exaroton Token
            "com.joker.OrzMC.installation",                     // 安装内记录的加密密钥
        ]
        #if DEBUG
        services.append("com.joker.OrzMC.sync.probe")           // 诊断探针（仅 DEBUG 会存在）
        #endif
        return services
    }

    /// 清掉本机资料。返回报告（而不是"全部成功/失败"），让界面能如实说清删了多少。
    @discardableResult
    static func clearLocalData() -> Report {
        var report = Report(removedRecords: 0, removedKeychainItems: 0, failed: [])

        // 1) 安装内记录（加密文件）：删之前数一下有几个 .record，便于界面回显。
        let directory = installationDirectory
        if let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let records = files.filter { $0.pathExtension == "record" }
            report.removedRecords = records.count
            for file in records {
                do { try FileManager.default.removeItem(at: file) }
                catch { report.failed.append(file.lastPathComponent) }
            }
        }
        // 目录本身留着（下次写入会重建），但把里面的残留一并清掉。
        if let leftovers = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for item in leftovers where item.pathExtension != "record" {
                try? FileManager.default.removeItem(at: item)
            }
        }

        // 2) 本机 Keychain 项（`.device` 档位 + 安装密钥）。
        for service in localKeychainServices {
            report.removedKeychainItems += deleteAllItems(service: service, failed: &report.failed)
        }

        return report
    }

    /// 删除某个 service 下的**所有** generic password（不指定 account）。
    private static func deleteAllItems(service: String, failed: inout [String]) -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else { return 0 }
        let items: [[String: Any]]
        if let array = result as? [[String: Any]] { items = array }
        else if let single = result as? [String: Any] { items = [single] }
        else { return 0 }

        var removed = 0
        for item in items {
            guard let account = item[kSecAttrAccount as String] as? String else { continue }
            let deleteQuery: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ]
            let deleteStatus = SecItemDelete(deleteQuery as CFDictionary)
            if deleteStatus == errSecSuccess { removed += 1 }
            else if deleteStatus != errSecItemNotFound { failed.append("\(service)/\(account)") }
        }
        return removed
    }
}
