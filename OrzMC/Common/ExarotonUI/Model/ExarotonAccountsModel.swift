import Foundation
import Observation

struct ExarotonAccount: Identifiable, Codable, Equatable {
    let id: UUID
    var label: String
}

/// Metadata is non-secret; each token has its own Keychain item. Models never share mutable credentials.
@MainActor
@Observable
final class ExarotonAccountsModel {
    private(set) var accounts: [ExarotonAccount] = []
    private(set) var models: [UUID: ExarotonServerModel] = [:]
    var errorMessage: String?
    private let defaults: UserDefaults
    private let loadToken: (String) -> String?
    private let saveToken: (String, String) throws -> Void
    private let deleteToken: (String) throws -> Void
    static let accountsKey = "EXAROTON_ACCOUNTS"
    static func tokenKey(_ id: UUID) -> String { "exaroton.account." + id.uuidString }

    init(
        defaults: UserDefaults = .standard,
        loadToken: @escaping (String) -> String? = { KeychainTokenStore.load(key: $0) },
        saveToken: @escaping (String, String) throws -> Void = { try KeychainTokenStore.save($0, key: $1) },
        deleteToken: @escaping (String) throws -> Void = { try KeychainTokenStore.delete(key: $0) }
    ) {
        self.defaults = defaults
        self.loadToken = loadToken
        self.saveToken = saveToken
        self.deleteToken = deleteToken
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["ORZMC_DEMO_FAKE_SERVER"] == "1" || !(env["ORZMC_DEMO_TOKEN"] ?? "").isEmpty {
            stop()
            let count = env["ORZMC_DEMO_MULTI_ACCOUNT"] == "1" ? 2 : 1
            for index in 1...count {
                let account = ExarotonAccount(id: UUID(), label: "exaroton \(index)")
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
            let legacy = loadToken(legacyKey) ?? defaults.string(forKey: legacyKey) ?? ""
            if !legacy.isEmpty, save(id: nil, label: "exaroton", token: legacy) {
                try? deleteToken(legacyKey)
                defaults.removeObject(forKey: legacyKey)
            }
        }
        for account in accounts where models[account.id] == nil {
            models[account.id] = ExarotonServerModel(accountToken: loadToken(Self.tokenKey(account.id)) ?? "")
        }

    }

    @discardableResult
    func save(id: UUID?, label: String, token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        let accountID = id ?? UUID()
        guard id == nil || accounts.contains(where: { $0.id == accountID }) else { return false }
        let key = Self.tokenKey(accountID)
        let credential = trimmed.isEmpty && id != nil ? loadToken(key) ?? "" : trimmed
        guard !credential.isEmpty else {
            errorMessage = String(localized: "The API key is empty.")
            return false
        }
        guard !accounts.contains(where: { $0.id != accountID && loadToken(Self.tokenKey($0.id)) == credential }) else {
            errorMessage = String(localized: "This account is already added.", comment: "Duplicate credential in provider")
            return false
        }
        do {
            try saveToken(credential, key)
            let name = label.trimmingCharacters(in: .whitespacesAndNewlines)
            let account = ExarotonAccount(id: accountID, label: name.isEmpty ? "exaroton" : name)
            var updated = accounts
            if let index = updated.firstIndex(where: { $0.id == accountID }) { updated[index] = account }
            else { updated.append(account) }
            let data = try JSONEncoder().encode(updated)
            defaults.set(data, forKey: Self.accountsKey)
            models[accountID]?.stopBackgroundRefresh()
            models[accountID]?.stopConnect()
            models[accountID] = ExarotonServerModel(accountToken: credential)
            accounts = updated
            errorMessage = nil
            return true
        } catch {
            errorMessage = String(localized: "Could not save account credentials. Please try again.", comment: "Keychain persistence failure")
            return false
        }
    }

    func remove(_ id: UUID) {
        do {
            try deleteToken(Self.tokenKey(id))
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
