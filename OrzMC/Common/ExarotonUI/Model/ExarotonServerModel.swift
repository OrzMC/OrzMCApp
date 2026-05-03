//
//  ExarotonServerModel.swift
//  OrzMC
//
//  Created by joker on 2024/5/17.
//

import ExarotonHTTP
import ExarotonWebSocket
import OpenAPIRuntime
import OpenAPIURLSession
import Security
import SwiftUI

@MainActor
@Observable
final class ExarotonServerModel {

    var path = NavigationPath()

    static let accountTokenPersistentKey = "EXAROTON_TOKEN"

    @ObservationIgnored
    var token: String {
        get {
            if let token = KeychainTokenStore.load(key: Self.accountTokenPersistentKey) {
                return token
            }
            let legacyToken = UserDefaults.standard.string(forKey: Self.accountTokenPersistentKey) ?? ""
            if !legacyToken.isEmpty {
                try? KeychainTokenStore.save(legacyToken, key: Self.accountTokenPersistentKey)
                UserDefaults.standard.removeObject(forKey: Self.accountTokenPersistentKey)
            }
            return legacyToken
        }
        set {
            let trimmedToken = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedToken.isEmpty {
                try? KeychainTokenStore.delete(key: Self.accountTokenPersistentKey)
                UserDefaults.standard.removeObject(forKey: Self.accountTokenPersistentKey)
            } else {
                try? KeychainTokenStore.save(trimmedToken, key: Self.accountTokenPersistentKey)
            }
        }
    }


    // HTTP Client
    @ObservationIgnored
    var httpClient: Client? {
        guard let serverURL = try? Servers.Server1.url() else {
            errorMessage = "Exaroton server URL is invalid."
            return nil
        }
        return Client(
            serverURL: serverURL,
            transport: URLSessionTransport(),
            middlewares: [AuthenticationMiddleware(token: token)]
        )
    }

    var servers = [ExarotonServer]()
    var creditPools = [ExarotonCreditPool]()
    var errorMessage: String?
    var statusMessage: String?

    // WebSocket Client
    @ObservationIgnored
    var websocket: ExarotonWebSocketAPI?
    @ObservationIgnored
    var websocketServerID: String?

    var readyServerID: String?
    var isConnected: Bool = false
    var disconnectedReason: String?
    var statusChangedServer: ExarotonWebSocket.Server?
    var streamStarted: ExarotonWebSocket.StreamCategory?
    var streamStopped: ExarotonWebSocket.StreamCategory?
    var consoleLine: String?
    var consoleLines = [String]()
    var tickChanged: ExarotonWebSocket.Tick?
    var statsChanged: ExarotonWebSocket.Stats?
    var heapChanged: ExarotonWebSocket.Heap?
}

private enum KeychainTokenStore {
    enum KeychainError: Error {
        case unhandledStatus(OSStatus)
    }

    static func load(key: String) -> String? {
        var query = baseQuery(key: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func save(_ token: String, key: String) throws {
        let data = Data(token.utf8)
        var query = baseQuery(key: key)
        let attributes = [kSecValueData as String: data]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unhandledStatus(status)
        }
    }

    static func delete(key: String) throws {
        let status = SecItemDelete(baseQuery(key: key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private static func baseQuery(key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Bundle.main.bundleIdentifier ?? "OrzMC",
            kSecAttrAccount as String: key
        ]
    }
}
