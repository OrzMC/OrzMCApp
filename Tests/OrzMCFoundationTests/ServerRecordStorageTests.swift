import Foundation
import XCTest
@testable import OrzMCFoundation

final class ServerRecordStorageTests: XCTestCase {
    private final class MemoryBackend: ServerRecordBackend {
        let identity = UUID().uuidString
        var values: [ServerStorageRecord] = []
        var rejectWrite = false
        var hideWritten = false
        var rejectRemove = false
        var onWrite: (() -> Void)?
        func records() throws -> [ServerStorageRecord] { hideWritten ? [] : values }
        func write(_ record: ServerStorageRecord) throws {
            if rejectWrite { throw TestError.failure }
            values.removeAll { $0.id == record.id && $0.provider == record.provider }
            values.append(record)
            onWrite?()
        }
        func remove(id: UUID, provider: String) throws {
            if rejectRemove { throw TestError.failure }
            values.removeAll { $0.id == id && $0.provider == provider }
        }
    }
    private enum TestError: Error { case failure }
    private let record = ServerStorageRecord(id: UUID(), provider: "example", payload: Data("test".utf8))

    func testMoveVerifiesTargetBeforeRemovingSource() throws {
        let source = MemoryBackend(), target = MemoryBackend()
        source.values = [record]
        try ServerRecordMigration.move(record, from: source, to: target)
        XCTAssertTrue(source.values.isEmpty)
        XCTAssertEqual(target.values, [record])
    }

    func testWriteOrVerificationFailureKeepsSource() {
        let source = MemoryBackend(), target = MemoryBackend()
        source.values = [record]
        target.rejectWrite = true
        XCTAssertThrowsError(try ServerRecordMigration.move(record, from: source, to: target))
        XCTAssertEqual(source.values, [record])
        target.rejectWrite = false
        target.hideWritten = true
        XCTAssertThrowsError(try ServerRecordMigration.move(record, from: source, to: target))
        XCTAssertEqual(source.values, [record])
    }

    func testDeleteFailureRetainsBothCopies() {
        let source = MemoryBackend(), target = MemoryBackend()
        source.values = [record]
        source.rejectRemove = true
        XCTAssertThrowsError(try ServerRecordMigration.move(record, from: source, to: target))
        XCTAssertEqual(source.values, [record])
        XCTAssertEqual(target.values, [record])
    }

    func testMoveDoesNotDeleteSameBackendOrOverwriteConflict() {
        let source = MemoryBackend(), target = MemoryBackend()
        source.values = [record]
        XCTAssertThrowsError(try ServerRecordMigration.move(record, from: source, to: source))
        XCTAssertEqual(source.values, [record])
        let conflict = ServerStorageRecord(id: record.id, provider: record.provider, payload: Data("different".utf8))
        target.values = [conflict]
        XCTAssertThrowsError(try ServerRecordMigration.move(record, from: source, to: target))
        XCTAssertEqual(source.values, [record])
        XCTAssertEqual(target.values, [conflict])
    }

    func testMoveDoesNotDeleteAChangedSource() {
        let source = MemoryBackend(), target = MemoryBackend()
        let updated = ServerStorageRecord(id: record.id, provider: record.provider, payload: Data("updated".utf8))
        source.values = [updated]
        XCTAssertThrowsError(try ServerRecordMigration.move(record, from: source, to: target))
        XCTAssertEqual(source.values, [updated])
        XCTAssertTrue(target.values.isEmpty)
    }

    func testMovePreservesSourceChangedDuringTargetWrite() {
        let source = MemoryBackend(), target = MemoryBackend()
        let updated = ServerStorageRecord(id: record.id, provider: record.provider, payload: Data("new".utf8))
        source.values = [record]
        target.onWrite = { source.values = [updated] }
        XCTAssertThrowsError(try ServerRecordMigration.move(record, from: source, to: target))
        XCTAssertEqual(source.values, [updated])
        XCTAssertEqual(target.values, [record])
    }

    func testInstallationRecordsAreEncryptedAndKeyLossDoesNotCreateANewKey() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "ServerRecordStorageTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let keychain = MemoryBackend()
        defer {
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = ServerRecordInstallation(directory: directory, defaults: defaults, keychain: keychain)
        let secret = ServerStorageRecord(id: UUID(), provider: "mcsm", payload: Data("sensitive-value".utf8))
        try store.write(secret)
        XCTAssertEqual(try store.records(), [secret])
        let file = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).first)
        XCTAssertNil(String(data: try Data(contentsOf: file), encoding: .utf8)?.range(of: "sensitive-value"))
        keychain.values.removeAll()
        XCTAssertThrowsError(try store.records())
        XCTAssertTrue(keychain.values.isEmpty, "a missing key must not be replaced while ciphertext exists")
    }
}

// MARK: - ServerRecordStore（作用域路由 + 迁移）

final class ServerRecordStoreTests: XCTestCase {
    private final class MemoryBackend: ServerRecordBackend {
        let identity = UUID().uuidString
        var values: [ServerStorageRecord] = []
        var failure: Error?
        func records() throws -> [ServerStorageRecord] {
            if let failure { throw failure }
            return values
        }
        func write(_ record: ServerStorageRecord) throws {
            if let failure { throw failure }
            values.removeAll { $0.id == record.id && $0.provider == record.provider }
            values.append(record)
        }
        func remove(id: UUID, provider: String) throws {
            if let failure { throw failure }
            values.removeAll { $0.id == id && $0.provider == provider }
        }
    }

    private enum TestError: Error { case unavailable }

    private let record = ServerStorageRecord(id: UUID(), provider: "example", payload: Data("payload".utf8))

    private func makeStore(iCloud: MemoryBackend? = MemoryBackend())
        -> (ServerRecordStore, MemoryBackend, MemoryBackend, MemoryBackend?) {
        let installation = MemoryBackend(), device = MemoryBackend()
        let store = ServerRecordStore(backends: .init(
            installation: installation, device: device, iCloud: iCloud as (any ServerRecordBackend)?
        ))
        return (store, installation, device, iCloud)
    }

    func testRoutesEachModeToItsBackend() throws {
        let (store, installation, device, iCloud) = makeStore()
        try store.write(record, mode: .installation)
        try store.write(record, mode: .device)
        try store.write(record, mode: .iCloud)

        XCTAssertEqual(installation.values.count, 1)
        XCTAssertEqual(device.values.count, 1)
        XCTAssertEqual(iCloud?.values.count, 1)
        XCTAssertEqual(try store.record(id: record.id, provider: record.provider, mode: .device), record)
        XCTAssertEqual(try store.record(id: record.id, provider: record.provider, mode: .installation), record)
    }

    func testUnavailableICloudIsAnErrorNotAnEmptyResult() {
        let (store, _, _, _) = makeStore(iCloud: nil)
        XCTAssertThrowsError(try store.write(record, mode: .iCloud)) { error in
            XCTAssertEqual(error as? ServerRecordStore.Failure, .backendUnavailable(.iCloud))
        }
        XCTAssertThrowsError(try store.record(id: record.id, provider: record.provider, mode: .iCloud))
    }

    func testInaccessibleBackendPropagatesInsteadOfLookingEmpty() {
        let (store, _, device, _) = makeStore()
        device.failure = TestError.unavailable
        XCTAssertThrowsError(try store.record(id: record.id, provider: record.provider, mode: .device))
    }

    func testMoveWritesTargetBeforeRemovingSource() throws {
        let (store, installation, device, _) = makeStore()
        try store.write(record, mode: .installation)
        try store.move(id: record.id, provider: record.provider, from: .installation, to: .device)
        XCTAssertTrue(installation.values.isEmpty)
        XCTAssertEqual(device.values, [record])
    }

    func testMoveToSameModeIsNoop() throws {
        let (store, installation, _, _) = makeStore()
        try store.write(record, mode: .installation)
        try store.move(id: record.id, provider: record.provider, from: .installation, to: .installation)
        XCTAssertEqual(installation.values, [record])
    }

    func testMoveFromEmptySourceFailsWithoutTouchingTarget() {
        let (store, _, device, _) = makeStore()
        XCTAssertThrowsError(
            try store.move(id: record.id, provider: record.provider, from: .installation, to: .device)
        ) { error in
            XCTAssertEqual(error as? ServerRecordStore.Failure, .sourceMissing)
        }
        XCTAssertTrue(device.values.isEmpty)
    }

    func testMoveRefusesToOverwriteDifferentPayload() throws {
        let (store, installation, device, _) = makeStore()
        try store.write(record, mode: .installation)
        let other = ServerStorageRecord(id: record.id, provider: record.provider, payload: Data("newer".utf8))
        try store.write(other, mode: .device)
        XCTAssertThrowsError(
            try store.move(id: record.id, provider: record.provider, from: .installation, to: .device)
        ) { error in
            XCTAssertEqual(error as? ServerRecordStore.Failure, .conflict)
        }
        XCTAssertEqual(device.values, [other], "冲突时不能覆盖目标")
        XCTAssertEqual(installation.values, [record], "冲突时不能删来源")
    }

    func testMoveRetryCleansUpSourceWhenTargetAlreadyHasSameCopy() throws {
        let (store, installation, device, _) = makeStore()
        try store.write(record, mode: .installation)
        try store.write(record, mode: .device)   // 上次迁移写完但没删源
        try store.move(id: record.id, provider: record.provider, from: .installation, to: .device)
        XCTAssertTrue(installation.values.isEmpty)
        XCTAssertEqual(device.values, [record])
    }

    func testRemoveDeletesFromEveryBackend() throws {
        let (store, installation, device, iCloud) = makeStore()
        try store.write(record, mode: .installation)
        try store.write(record, mode: .device)
        try store.write(record, mode: .iCloud)
        try store.remove(id: record.id, provider: record.provider)
        XCTAssertTrue(installation.values.isEmpty)
        XCTAssertTrue(device.values.isEmpty)
        XCTAssertTrue(iCloud?.values.isEmpty ?? false)
    }

    func testRemoveReportsFailureButStillClearsOtherBackends() throws {
        let (store, installation, device, _) = makeStore()
        try store.write(record, mode: .installation)
        try store.write(record, mode: .device)
        installation.failure = TestError.unavailable
        XCTAssertThrowsError(try store.remove(id: record.id, provider: record.provider))
        XCTAssertTrue(device.values.isEmpty, "一个后端失败也要继续删其它后端")
    }
}
