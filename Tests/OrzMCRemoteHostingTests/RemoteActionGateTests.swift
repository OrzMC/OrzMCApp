import XCTest
@testable import OrzMCRemoteHosting

/// 远程在途操作互斥：同实例单请求、生命周期与内存互斥、实例之间互不阻塞。
final class RemoteActionGateTests: XCTestCase {
    func testSecondActionOnSameServerIsRejected() {
        var gate = RemoteActionGate()
        XCTAssertTrue(gate.beginAction(serverID: "a"))
        XCTAssertTrue(gate.isBusy(serverID: "a"))
        XCTAssertFalse(gate.beginAction(serverID: "a"), "在途时必须拒绝第二次提交")
        XCTAssertFalse(gate.beginMemoryChange(serverID: "a"))
    }

    func testLifecycleAndMemoryAreMutuallyExclusive() {
        var gate = RemoteActionGate()
        XCTAssertTrue(gate.beginMemoryChange(serverID: "a"))
        XCTAssertFalse(gate.beginAction(serverID: "a"))
        XCTAssertFalse(gate.beginMemoryChange(serverID: "a"))

        gate.endMemoryChange(serverID: "a")
        XCTAssertFalse(gate.isBusy(serverID: "a"))
        XCTAssertTrue(gate.beginAction(serverID: "a"))
        XCTAssertFalse(gate.beginMemoryChange(serverID: "a"), "生命周期动作在途时不能改内存")
    }

    func testDifferentServersDoNotBlockEachOther() {
        var gate = RemoteActionGate()
        XCTAssertTrue(gate.beginAction(serverID: "a"))
        XCTAssertTrue(gate.beginAction(serverID: "b"))
        XCTAssertTrue(gate.beginMemoryChange(serverID: "c"))
        XCTAssertEqual(gate.pendingActions, ["a", "b"])
        XCTAssertEqual(gate.pendingMemoryChanges, ["c"])
        XCTAssertTrue(gate.isBusy)
    }

    func testEndingReleasesInstanceAndGlobalBusy() {
        var gate = RemoteActionGate()
        XCTAssertFalse(gate.isBusy)
        XCTAssertTrue(gate.beginAction(serverID: "a"))
        XCTAssertTrue(gate.isBusy)
        gate.endAction(serverID: "a")
        XCTAssertFalse(gate.isBusy)
        XCTAssertTrue(gate.beginAction(serverID: "a"), "请求结束后必须能重试")
    }

    func testResetClearsEverything() {
        var gate = RemoteActionGate()
        _ = gate.beginAction(serverID: "a")
        _ = gate.beginMemoryChange(serverID: "b")
        gate.reset()
        XCTAssertEqual(gate, RemoteActionGate())
    }
}
