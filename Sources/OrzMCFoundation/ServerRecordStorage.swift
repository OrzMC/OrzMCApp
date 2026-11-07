import Foundation

/// How a single server or provider account survives application removal.
public enum ServerRecordStorageMode: String, Codable, CaseIterable, Sendable {
    case installation
    case device
    case iCloud
}

/// An opaque, provider-owned payload. This value may contain credentials and must only be
/// handed to a backend designed for secrets; never write it to UserDefaults or logs.
public struct ServerStorageRecord: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let provider: String
    public let payload: Data

    public init(id: UUID, provider: String, payload: Data) {
        self.id = id
        self.provider = provider
        self.payload = payload
    }
}

/// Backend implementations report failures rather than treating inaccessible storage as empty.
public protocol ServerRecordBackend {
    var identity: String { get }
    func records() throws -> [ServerStorageRecord]
    func write(_ record: ServerStorageRecord) throws
    func remove(id: UUID, provider: String) throws
}

/// Moves a record only after a read-back of its new copy. If removal fails, both copies
/// remain; the caller can report the incomplete move without destroying the original.
/// The backend protocol cannot atomically compare and delete, so callers must serialize
/// local edits and must not use this helper to delete an asynchronously changing cloud item.
public struct ServerRecordMigration {
    public enum Failure: Error, Equatable {
        case verificationFailed
        case sameBackend
        case conflictingRecord
        case sourceChanged
    }

    public static func move(_ record: ServerStorageRecord, from source: any ServerRecordBackend,
                            to destination: any ServerRecordBackend) throws {
        guard source.identity != destination.identity else { throw Failure.sameBackend }
        guard try source.records().contains(record) else { throw Failure.sourceChanged }
        if let existing = try destination.records().first(where: { $0.id == record.id && $0.provider == record.provider }),
           existing != record { throw Failure.conflictingRecord }
        try destination.write(record)
        guard try destination.records().contains(record) else { throw Failure.verificationFailed }
        guard try source.records().contains(record) else { throw Failure.sourceChanged }
        try source.remove(id: record.id, provider: record.provider)
    }
}
