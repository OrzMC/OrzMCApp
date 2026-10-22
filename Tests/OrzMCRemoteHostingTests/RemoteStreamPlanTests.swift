import XCTest
@testable import OrzMCRemoteHosting

/// 远程流订阅决策：只在「已连接 + 在线」时订阅；停止时不重复发指令。
final class RemoteStreamPlanTests: XCTestCase {
    private enum Stream: Hashable, Sendable { case console, tick, stats }

    func testOnlyConnectedAndOnlineStreams() {
        XCTAssertTrue(RemoteStreamingPolicy.shouldStream(isConnected: true, isServerOnline: true))
        XCTAssertFalse(RemoteStreamingPolicy.shouldStream(isConnected: false, isServerOnline: true))
        XCTAssertFalse(RemoteStreamingPolicy.shouldStream(isConnected: true, isServerOnline: false))
    }

    func testStartingOnlyOpensMissingStreams() {
        let plan = RemoteStreamPlan<Stream>.make(
            active: [.console],
            all: [.console, .tick, .stats],
            isEnabled: true
        )
        XCTAssertEqual(plan.start, [.tick, .stats])
        XCTAssertTrue(plan.stop.isEmpty)
    }

    func testStoppingOnlyClosesActiveStreams() {
        let plan = RemoteStreamPlan<Stream>.make(
            active: [.console, .stats],
            all: [.console, .tick, .stats],
            isEnabled: false
        )
        XCTAssertEqual(plan.stop, [.console, .stats])
        XCTAssertTrue(plan.start.isEmpty, "没订阅的流不能再发 stop")
    }

    func testSteadyStatePlansNothing() {
        XCTAssertTrue(RemoteStreamPlan<Stream>.make(active: [.console, .tick, .stats], all: [.console, .tick, .stats], isEnabled: true).isEmpty)
        XCTAssertTrue(RemoteStreamPlan<Stream>.make(active: [], all: [.console], isEnabled: false).isEmpty)
    }
}
