import CryptoKit
import Foundation
import Security

/// Encrypted records tied to an installation. The random encryption key is held in the
/// local Keychain; the installation identifier and ciphertext live in the app container.
/// Removing an iOS app removes the ciphertext. macOS app deletion alone does not ensure
/// its support files are removed, so callers must provide an explicit clear-data action.
public final class ServerRecordInstallation: ServerRecordBackend {
    public enum Failure: Error { case invalidKey, invalidRecord }

    // Several views may request the first record at once. Creating two installation
    // keys concurrently could otherwise make the first ciphertext unreadable.
    private static let keyCreationLock = NSLock()

    private let directory: URL
    private let defaults: UserDefaults
    private let keychain: any ServerRecordBackend
    private let installationKey: String
    private let manager: FileManager
    public var identity: String { "installation:\(directory.standardizedFileURL.path)" }

    public init(directory: URL, defaults: UserDefaults = .standard,
                keychain: any ServerRecordBackend, installationKey: String = "serverStorage.installationID",
                manager: FileManager = .default) {
        self.directory = directory
        self.defaults = defaults
        self.keychain = keychain
        self.installationKey = installationKey
        self.manager = manager
    }

    private func encryptionKey(allowCreate: Bool) throws -> SymmetricKey {
        Self.keyCreationLock.lock()
        defer { Self.keyCreationLock.unlock() }
        let installationID: UUID
        if let saved = defaults.string(forKey: installationKey), let id = UUID(uuidString: saved) {
            installationID = id
        } else if allowCreate {
            installationID = UUID()
            defaults.set(installationID.uuidString, forKey: installationKey)
        } else {
            throw Failure.invalidKey
        }
        if let existing = try keychain.records().first(where: { $0.id == installationID && $0.provider == "installation-key" }) {
            guard existing.payload.count == 32 else { throw Failure.invalidKey }
            return SymmetricKey(data: existing.payload)
        }
        guard allowCreate else { throw Failure.invalidKey }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        try keychain.write(ServerStorageRecord(id: installationID, provider: "installation-key", payload: data))
        guard try keychain.records().contains(where: { $0.id == installationID && $0.payload == data }) else {
            throw Failure.invalidKey
        }
        return key
    }

    private func fileURL(id: UUID, provider: String) -> URL {
        let name = Data(provider.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "+", with: "-")
        return directory.appendingPathComponent("\(name).\(id.uuidString).record", isDirectory: false)
    }

    public func records() throws -> [ServerStorageRecord] {
        guard manager.fileExists(atPath: directory.path) else { return [] }
        let files = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "record" }
        guard !files.isEmpty else { return [] }
        let key = try encryptionKey(allowCreate: false)
        return try files.map { file in
            let sealed = try AES.GCM.SealedBox(combined: Data(contentsOf: file))
            let plain = try AES.GCM.open(sealed, using: key)
            let record = try JSONDecoder().decode(ServerStorageRecord.self, from: plain)
            guard file.lastPathComponent == fileURL(id: record.id, provider: record.provider).lastPathComponent else {
                throw Failure.invalidRecord
            }
            return record
        }
    }

    public func write(_ record: ServerStorageRecord) throws {
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        var directory = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let existing = try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .contains { $0.pathExtension == "record" }
        let key = try encryptionKey(allowCreate: !existing)
        let plain = try JSONEncoder().encode(record)
        guard let encrypted = try AES.GCM.seal(plain, using: key).combined else { throw Failure.invalidRecord }
        let url = fileURL(id: record.id, provider: record.provider)
        try encrypted.write(to: url, options: [.atomic, .completeFileProtection])
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    public func remove(id: UUID, provider: String) throws {
        let url = fileURL(id: id, provider: provider)
        if manager.fileExists(atPath: url.path) { try manager.removeItem(at: url) }
    }
}
