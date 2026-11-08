import Foundation
import OrzMCFoundation
import Observation

struct ExarotonAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
    var autoName: Bool? = nil
    /// 这条账号（含 Token）的保存方式；老存档没有该字段 → `.device`（与升级前一致）。
    var storageMode: ServerRecordStorageMode = .device

    private enum CodingKeys: String, CodingKey { case id, label, autoName, storageMode }

    init(id: UUID, label: String, autoName: Bool? = nil, storageMode: ServerRecordStorageMode = .device) {
        self.id = id
        self.label = label
        self.autoName = autoName
        self.storageMode = storageMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        label = try c.decode(String.self, forKey: .label)
        autoName = try c.decodeIfPresent(Bool.self, forKey: .autoName)
        storageMode = try c.decodeIfPresent(ServerRecordStorageMode.self, forKey: .storageMode) ?? .device
    }

    var displayName: String {
        label.isEmpty || (label.lowercased() == "exaroton" && autoName == nil) ? String(localized: "Account") : label
    }
}

/// Metadata is non-secret; each token has its own Keychain item. Models never share mutable credentials.
@MainActor
@Observable
final class ExarotonAccountsModel {
    private(set) var accounts: [ExarotonAccount] = []
    private(set) var models: [UUID: ExarotonServerModel] = [:]
    var errorMessage: String?
    private var isDemo = false
    private let defaults: UserDefaults
    /// Token 读写：`(账号 id, 该账号的保存方式)` → 口令。档位跟着账号自己走。
    private let loadToken: (UUID, ServerRecordStorageMode) -> String?
    private let saveToken: (String, UUID, ServerRecordStorageMode) throws -> Void
    private let deleteToken: (UUID) throws -> Void
    static let accountsKey = "EXAROTON_ACCOUNTS"
    static func tokenKey(_ id: UUID) -> String { "exaroton.account." + id.uuidString }

    init(
        defaults: UserDefaults = .standard,
        loadToken: @escaping (UUID, ServerRecordStorageMode) -> String? = {
            ServerSecretsStore.secret(id: $0, provider: .exarotonToken, mode: $1)
        },
        saveToken: @escaping (String, UUID, ServerRecordStorageMode) throws -> Void = { secret, id, mode in
            guard ServerSecretsStore.save(secret, id: id, provider: .exarotonToken, mode: mode) else {
                throw ServerSecretsStore.Failure.writeFailed
            }
        },
        deleteToken: @escaping (UUID) throws -> Void = { id in
            ServerSecretsStore.remove(id: id, provider: .exarotonToken)
        }
    ) {
        self.defaults = defaults
        self.loadToken = loadToken
        self.saveToken = saveToken
        self.deleteToken = deleteToken
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["ORZMC_DEMO_FAKE_SERVER"] == "1" || !(env["ORZMC_DEMO_TOKEN"] ?? "").isEmpty {
            isDemo = true
            stop()
            let count = env["ORZMC_DEMO_MULTI_ACCOUNT"] == "1" ? 2 : 1
            for index in 1...count {
                let account = ExarotonAccount(id: UUID(), label: count == 1 ? "" : "Exaroton \(index)", autoName: count == 1)
                accounts.append(account)
                models[account.id] = ExarotonServerModel(accountToken: env["ORZMC_DEMO_FAKE_SERVER"] == "1" ? "" : env["ORZMC_DEMO_TOKEN"])
            }
            return
        }
        #endif
        if let data = defaults.data(forKey: Self.accountsKey) {
            guard let decoded = try? JSONDecoder().decode([ExarotonAccount].self, from: data) else {
                errorMessage = String(localized: "Could not load saved accounts.", comment: "Account metadata decoding failed")
                return
            }
            accounts = decoded
        } else {
            // Keep the legacy credential until both the new Keychain item and metadata exist.
            let legacyKey = ExarotonServerModel.accountTokenPersistentKey
            let legacy = defaults.string(forKey: legacyKey) ?? ""
            if !legacy.isEmpty, save(id: nil, label: "", token: legacy) {
                defaults.removeObject(forKey: legacyKey)
            }
        }
        for account in accounts where models[account.id] == nil {
            models[account.id] = ExarotonServerModel(
                accountToken: loadToken(account.id, account.storageMode) ?? ""
            )
        }
        // 启动即与云端合并（iCloud 档位的账号在另一端新增/删除都能反映过来）。
        syncWithCloud()
        for account in accounts where models[account.id] == nil {
            models[account.id] = ExarotonServerModel(
                accountToken: loadToken(account.id, account.storageMode) ?? ""
            )
        }
    }

    @discardableResult
    func save(
        id: UUID?,
        label: String,
        token: String,
        storageMode: ServerRecordStorageMode? = nil
    ) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountID = id ?? UUID()
        guard id == nil || accounts.contains(where: { $0.id == accountID }) else { return false }
        let previousAccount = accounts.first { $0.id == accountID }
        let existingMode = storageMode ?? previousAccount?.storageMode ?? .device
        // 保存方式变了：先把已存的 Token 搬到新后端（失败就保留原数据并报错）。
        if let previousAccount, previousAccount.storageMode != existingMode {
            do {
                try StorageModeMigration.apply(
                    id: accountID,
                    provider: .exarotonToken,
                    from: previousAccount.storageMode,
                    to: existingMode
                )
            } catch {
                errorMessage = error.localizedDescription
                return false
            }
        }
        let credential = trimmed.isEmpty && id != nil ? loadToken(accountID, existingMode) ?? "" : trimmed
        guard !credential.isEmpty else {
            errorMessage = String(localized: "The API key is empty.")
            return false
        }
        guard !accounts.contains(where: {
            $0.id != accountID && loadToken($0.id, $0.storageMode) == credential
        }) else {
            errorMessage = String(localized: "This account is already added.", comment: "Duplicate credential in provider")
            return false
        }
        do {
            try saveToken(credential, accountID, existingMode)
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let previous = accounts.first(where: { $0.id == accountID })
            let automatic = name.isEmpty || (previous?.autoName == true && previous?.label == name)
            let account = ExarotonAccount(
                id: accountID, label: name, autoName: automatic, storageMode: existingMode
            )
            var updated = accounts
            if let index = updated.firstIndex(where: { $0.id == accountID }) { updated[index] = account }
            else { updated.append(account) }
            let data = try JSONEncoder().encode(updated)
            defaults.set(data, forKey: Self.accountsKey)
            models[accountID]?.stopBackgroundRefresh()
            models[accountID]?.stopConnect()
            models[accountID] = ExarotonServerModel(accountToken: credential)
            accounts = updated
            publishToCloud(account, token: credential)
            errorMessage = nil
            return true
        } catch {
            errorMessage = String(localized: "Could not save account credentials. Please try again.", comment: "Keychain persistence failure")
            return false
        }
    }

    /// Resolve only the placeholder; never overwrite an explicit user name or a newer model.
    func resolveDefaultName(
        for id: UUID,
        lookup: @MainActor (ExarotonServerModel) async throws -> String? = { model in
            let response = try await model.makeClient().getAccount()
            guard case .ok(let ok) = response else { return nil }
            return try ok.body.json.data?.name
        }
    ) async {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["ORZMC_DEMO_FAKE_SERVER"] == "1" { return }
        #endif
        guard let account = accounts.first(where: { $0.id == id }), (account.autoName ?? (account.label.lowercased() == "exaroton")),
              let model = models[id], !model.token.isEmpty else { return }
        do {
            guard let name = try await lookup(model)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !name.isEmpty, let index = accounts.firstIndex(where: { $0.id == id }),
                  (accounts[index].autoName ?? (accounts[index].label.lowercased() == "exaroton")),
                  models[id] === model else { return }
            guard accounts[index].label != name || accounts[index].autoName == nil else { return }
            var updated = accounts
            updated[index].label = name
            updated[index].autoName = true
            let data = try JSONEncoder().encode(updated)
            if !isDemo { defaults.set(data, forKey: Self.accountsKey) }
            accounts = updated
        } catch {
            // Keep the placeholder; the account and its servers remain usable offline.
        }
    }

    /// 把账号（名字 + Token）整条推到 iCloud；档位不是 iCloud 时清掉云端副本。
    private func publishToCloud(_ account: ExarotonAccount, token: String) {
        guard ServerSecretsStore.isAvailable(.iCloud) else { return }
        if account.storageMode == .iCloud {
            guard let config = try? JSONEncoder().encode(account) else { return }
            CloudRecords.push(id: account.id, kind: .exaroton, config: config, secret: token)
        } else {
            CloudRecords.remove(id: account.id, kind: .exaroton)
        }
    }

    /// 启动 / 回前台时合并云端账号。
    ///
    /// 去重口径：**同一个 Token 视为同一个账号**（本地可能用不同 id 建过同一账号，
    /// 按 id 合并会变成两条）。命中时用云端那条替换本地的，避免出现两份"海外服"。
    func syncWithCloud() {
        guard ServerSecretsStore.isAvailable(.iCloud) else { return }
        let entries = CloudRecords.pull()[.exaroton] ?? []
        guard !entries.isEmpty || accounts.contains(where: { $0.storageMode == .iCloud }) else { return }
        var updated = accounts
        var cloudIDs = Set<UUID>()
        var changed = false

        for entry in entries {
            guard var account = try? JSONDecoder().decode(ExarotonAccount.self, from: entry.config) else { continue }
            account.storageMode = .iCloud
            cloudIDs.insert(account.id)

            // 同 Token 的本机账号（可能是别的 id）→ 让位给云端这条。
            if let duplicate = updated.first(where: { $0.id != account.id && loadToken($0.id, $0.storageMode) == entry.secret }) {
                updated.removeAll { $0.id == duplicate.id }
                models[duplicate.id] = nil
                changed = true
            }
            if let index = updated.firstIndex(where: { $0.id == account.id }) {
                if updated[index] != account { updated[index] = account; changed = true }
            } else {
                updated.append(account)
                changed = true
            }
            if !entry.secret.isEmpty,
               loadToken(account.id, .iCloud) != entry.secret {
                try? saveToken(entry.secret, account.id, .iCloud)
            }
        }

        // ⚠️ 不做"云端没有就删本地"（读取失败/格式升级/延迟都会误删，2026-11-08 踩过）。
        _ = cloudIDs

        if changed {
            accounts = updated
            if let data = try? JSONEncoder().encode(updated) {
                defaults.set(data, forKey: Self.accountsKey)
            }
        }
    }

    func remove(_ id: UUID) {
        do {
            try deleteToken(id)
            CloudRecords.remove(id: id, kind: .exaroton)
            let updated = accounts.filter { $0.id != id }
            defaults.set(try JSONEncoder().encode(updated), forKey: Self.accountsKey)
            models[id]?.stopBackgroundRefresh()
            models[id]?.stopConnect()
            models[id] = nil
            accounts = updated
            errorMessage = nil
        } catch {
            errorMessage = String(localized: "Could not remove account credentials. Please try again.", comment: "Keychain deletion failure")
        }
    }

    func setActive(_ active: Bool) {
        for model in models.values {
            model.isSceneActive = active
            model.startBackgroundRefresh()
            if active && !model.token.isEmpty { Task { await model.reloadList() } }
        }
    }

    func stop() {
        for model in models.values { model.stopBackgroundRefresh(); model.stopConnect() }
    }
}
