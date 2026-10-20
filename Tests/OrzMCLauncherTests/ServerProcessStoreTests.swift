import XCTest
import OrzMCFoundation
@testable import OrzMCLauncher

/// 进程登记表：**落盘**（重启不失忆）+ 只按**自己登记的 PID**探活（不再全机 `ps`）。
final class ServerProcessStoreTests: XCTestCase {
    private let key = ManagedServerKey(versionId: "1.21.5", softwareId: "Paper")

    func testRecordIsPersistedAndReloaded() {
        let persistence = InMemoryServerProcessPersistence()
        var store = ManagedServerProcessStore(persistence: persistence)
        store.record(ProcessIdentifier("4242"), for: key)

        // 模拟 app 重启：新 store 从持久化恢复
        let reloaded = ManagedServerProcessStore(persistence: persistence)
        XCTAssertEqual(reloaded.processId(for: key), ProcessIdentifier("4242"))
        XCTAssertEqual(persistence.load(), [key.rawValue: "4242"])
    }

    func testRefreshDropsDeadProcessesAndPersists() {
        let persistence = InMemoryServerProcessPersistence()
        var store = ManagedServerProcessStore(persistence: persistence)
        store.record(ProcessIdentifier("1"), for: key)
        store.record(
            ProcessIdentifier("2"),
            for: ManagedServerKey(versionId: "1.20.6", softwareId: "Vanilla")
        )

        // 只剩 pid 1 活着
        store.refresh(runningProcessIds: [ProcessIdentifier("1")])

        XCTAssertEqual(store.registeredProcessIds(), [ProcessIdentifier("1")])
        XCTAssertEqual(persistence.load().count, 1, "修剪结果要落盘，否则重启后又冒出来")
    }

    func testRemoveAndRemoveAllPersist() {
        let persistence = InMemoryServerProcessPersistence()
        var store = ManagedServerProcessStore(persistence: persistence)
        store.record(ProcessIdentifier("7"), for: key)
        store.removeProcess(for: key)
        XCTAssertEqual(persistence.load(), [:])

        store.record(ProcessIdentifier("8"), for: key)
        store.removeAll()
        XCTAssertEqual(persistence.load(), [:])
    }

    func testUnregisteredProcessIsNeverReported() {
        // 关键回归：以前用全机 `ps ... nogui` 扫描，会把**别人启动的**服务端也当成自己的，
        // `Stop All` 于是误杀。现在只认登记过的 PID。
        let store = ManagedServerProcessStore(persistence: InMemoryServerProcessPersistence())
        XCTAssertTrue(store.registeredProcessIds().isEmpty)
        XCTAssertEqual(store.processId(for: key), nil)
    }

    func testLivenessProbeRejectsNonPositivePid() {
        let probe = KernelProcessLivenessProbe()
        XCTAssertFalse(probe.isAlive(ProcessIdentifier("not-a-pid")))
        XCTAssertFalse(probe.isAlive(ProcessIdentifier("0")))
        XCTAssertFalse(probe.isAlive(ProcessIdentifier("-1")))
        // 自己是活的（`kill(getpid(), 0)` 必成功）。
        XCTAssertTrue(probe.isAlive(ProcessIdentifier(String(getpid()))))
    }

    func testPersistenceIgnoresCorruptFile() {
        let path = NSTemporaryDirectory() + "orzmc-servers-\(UUID().uuidString).json"
        try? "{not json".write(toFile: path, atomically: true, encoding: .utf8)
        XCTAssertEqual(FileServerProcessPersistence(path: path).load(), [:], "坏文件当空，不崩")
    }

    func testPersistenceRoundTrip() {
        let path = NSTemporaryDirectory() + "orzmc-servers-\(UUID().uuidString).json"
        let persistence = FileServerProcessPersistence(path: path)
        persistence.save(["1.21.5#Paper": "999"])
        XCTAssertEqual(persistence.load(), ["1.21.5#Paper": "999"])
    }
}
