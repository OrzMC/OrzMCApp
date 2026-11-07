import Foundation
import Security

/// Stores complete provider records as individual Keychain items. Cloud items use an
/// explicitly supplied shared access group so macOS and iOS can address the same items.
public struct ServerRecordKeychain: ServerRecordBackend {
    public struct Failure: Error, Equatable {
        public let status: OSStatus
        public init(_ status: OSStatus) { self.status = status }
    }

    private let service: String
    private let synchronizable: Bool
    private let accessGroup: String?
    public var identity: String { "keychain:\(service):\(synchronizable):\(accessGroup ?? "default")" }

    public init(service: String, synchronizable: Bool, accessGroup: String? = nil) {
        self.service = service
        self.synchronizable = synchronizable
        self.accessGroup = accessGroup
    }

    private var baseQuery: [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrSynchronizable as String: synchronizable,
            kSecUseDataProtectionKeychain as String: true,
        ]
        if let accessGroup { query[kSecAttrAccessGroup as String] = accessGroup }
        return query
    }

    private func query(id: UUID, provider: String) -> [String: Any] {
        var result = baseQuery
        result[kSecAttrAccount as String] = "\(provider).\(id.uuidString)"
        return result
    }

    public func records() throws -> [ServerStorageRecord] {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitAll
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess else { throw Failure(status) }
        let values: [Data]
        if let array = result as? [Data] { values = array }
        else if let data = result as? Data { values = [data] }
        else { throw Failure(errSecDecode) }
        return try values.map { try JSONDecoder().decode(ServerStorageRecord.self, from: $0) }
    }

    public func write(_ record: ServerStorageRecord) throws {
        let data = try JSONEncoder().encode(record)
        var query = query(id: record.id, provider: record.provider)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = synchronizable
                ? kSecAttrAccessibleAfterFirstUnlock : kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let added = SecItemAdd(query as CFDictionary, nil)
            guard added == errSecSuccess else { throw Failure(added) }
        } else if status != errSecSuccess {
            throw Failure(status)
        }
    }

    public func remove(id: UUID, provider: String) throws {
        let status = SecItemDelete(query(id: id, provider: provider) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Failure(status) }
    }
}
