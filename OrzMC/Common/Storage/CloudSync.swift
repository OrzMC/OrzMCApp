//
//  CloudSync.swift
//  OrzMC
//
//  启动 / 回前台时把 **iCloud 里的整条记录** 合并进本机存储。
//
//  为什么放在应用层、而不是各个 Model 的 init：
//  macOS 上「我的服务器 / 远程托管」在**独立窗口**里，只有打开那个窗口才会创建 Model；
//  如果同步挂在 Model.init 上，用户不开窗口就永远不同步（2026-11-08 实测踩到）。
//  这里直接读写三个 UserDefaults 存储，与窗口无关。
//

import Foundation
import OrzMCFoundation
import OrzMCLauncher

@MainActor
enum CloudSync {

    /// 合并一次。返回合并了多少条（仅用于 DEBUG 日志）。
    @discardableResult
    static func run() -> Int {
        guard ServerSecretsStore.isAvailable(.iCloud) else { return 0 }
        let cloud = CloudRecords.pull()
        guard !cloud.isEmpty else { return 0 }
        var merged = 0
        merged += mergeSelfHosted(cloud[.selfHosted] ?? [])
        merged += mergeExaroton(cloud[.exaroton] ?? [])
        merged += mergeMCSM(cloud[.mcsm] ?? [])
        #if DEBUG
        if merged > 0 {
            FileHandle.standardError.write(Data("storage: cloudSync merged=\(merged)\n".utf8))
        }
        #endif
        return merged
    }

    // MARK: - 自建服务器

    private static func mergeSelfHosted(_ entries: [(id: UUID, config: Data, secret: String)]) -> Int {
        guard !entries.isEmpty else { return 0 }
        var profiles = SelfHostedProfilesStore.load()
        var merged = 0
        for entry in entries {
            guard var profile = try? JSONDecoder().decode(SelfHostedServerProfile.self, from: entry.config) else {
                continue
            }
            profile.storageMode = .iCloud
            if profiles.servers.first(where: { $0.id == profile.id }) != profile {
                if let index = profiles.servers.firstIndex(where: { $0.id == profile.id }) {
                    profiles.servers[index] = profile
                } else {
                    profiles.servers.append(profile)
                }
                merged += 1
            }
            if !entry.secret.isEmpty {
                _ = ServerSecretsStore.save(
                    entry.secret, id: entry.id, provider: .selfHostedRCON, mode: .iCloud
                )
            }
        }
        if merged > 0 { SelfHostedProfilesStore.save(profiles) }
        return merged
    }

    // MARK: - Exaroton

    private static func mergeExaroton(_ entries: [(id: UUID, config: Data, secret: String)]) -> Int {
        guard !entries.isEmpty else { return 0 }
        let defaults = UserDefaults.standard
        let key = ExarotonAccountsModel.accountsKey
        var accounts: [ExarotonAccount] = {
            guard let data = defaults.data(forKey: key),
                  let decoded = try? JSONDecoder().decode([ExarotonAccount].self, from: data)
            else { return [] }
            return decoded
        }()
        var merged = 0
        for entry in entries {
            guard var account = try? JSONDecoder().decode(ExarotonAccount.self, from: entry.config) else { continue }
            account.storageMode = .iCloud
            // 同一个 Token 视为同一个账号（本机可能用别的 id 建过）→ 用云端这条替换。
            if let duplicate = accounts.first(where: {
                $0.id != account.id
                    && ServerSecretsStore.secret(id: $0.id, provider: .exarotonToken, mode: $0.storageMode) == entry.secret
            }) {
                accounts.removeAll { $0.id == duplicate.id }
                merged += 1
            }
            if let index = accounts.firstIndex(where: { $0.id == account.id }) {
                if accounts[index] != account { accounts[index] = account; merged += 1 }
            } else {
                accounts.append(account)
                merged += 1
            }
            if !entry.secret.isEmpty {
                _ = ServerSecretsStore.save(
                    entry.secret, id: entry.id, provider: .exarotonToken, mode: .iCloud
                )
            }
        }
        if merged > 0, let data = try? JSONEncoder().encode(accounts) {
            defaults.set(data, forKey: key)
        }
        return merged
    }

    // MARK: - MCSManager

    private static func mergeMCSM(_ entries: [(id: UUID, config: Data, secret: String)]) -> Int {
        guard !entries.isEmpty else { return 0 }
        var panels = MCSManagerCredentials.panels()
        var merged = 0
        for entry in entries {
            guard var panel = try? JSONDecoder().decode(MCSManagerPanel.self, from: entry.config) else { continue }
            panel.storageMode = .iCloud
            if let duplicate = panels.first(where: { $0.id != panel.id && $0.url == panel.url }) {
                panels.removeAll { $0.id == duplicate.id }
                merged += 1
            }
            if let index = panels.firstIndex(where: { $0.id == panel.id }) {
                if panels[index] != panel { panels[index] = panel; merged += 1 }
            } else {
                panels.append(panel)
                merged += 1
            }
            if !entry.secret.isEmpty {
                _ = ServerSecretsStore.save(
                    entry.secret, id: entry.id, provider: .mcsmAPIKey, mode: .iCloud
                )
            }
        }
        if merged > 0 { MCSManagerCredentials.save(panels) }
        return merged
    }
}
