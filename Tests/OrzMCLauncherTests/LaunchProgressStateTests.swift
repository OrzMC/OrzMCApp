import XCTest
@testable import OrzMCLauncher

/// 进度状态（取代 GUI 里 6 个散装 `progress*` 字段）。
final class LaunchProgressStateTests: XCTestCase {
    func testIndefiniteWhenNoFraction() {
        let state = LaunchProgressState(label: "Downloading", completed: 3, total: nil, fraction: nil)
        XCTAssertTrue(state.isIndefinite)
        XCTAssertTrue(state.isRunning)
        XCTAssertFalse(state.isFinished)
        XCTAssertEqual(state.summary, "Downloading", "不定长只显示阶段，不画假百分比")
    }

    func testItemsSummary() {
        let state = LaunchProgressState(completed: 12, total: 60, unit: .items, fraction: 0.2)
        XCTAssertEqual(state.summary, "12 / 60")
        XCTAssertTrue(state.isRunning)
        XCTAssertFalse(state.isIndefinite)
    }

    func testBytesSummaryUsesHumanReadable() {
        let state = LaunchProgressState(
            completed: 1_048_576, total: 10_485_760, unit: .bytes, fraction: 0.1)
        XCTAssertTrue(state.summary.contains("/"), state.summary)
        XCTAssertEqual(state.summary.split(separator: "/").count, 2)
    }

    func testPercentFallbackAndFinished() {
        let state = LaunchProgressState(completed: 0, total: nil, fraction: 0.42)
        XCTAssertEqual(state.summary, "42%")
        XCTAssertTrue(state.isRunning)

        let done = LaunchProgressState(fraction: 1)
        XCTAssertTrue(done.isFinished)
        XCTAssertFalse(done.isRunning)
    }

    func testIdleShowsNothing() {
        XCTAssertFalse(LaunchProgressState.idle.isRunning)
        XCTAssertFalse(LaunchProgressState.idle.isFinished)
        XCTAssertEqual(LaunchProgressState.idle.summary, "")
    }

    func testGameModeIsDistinctFromEngineGameType() {
        // GUI 的 client/server 不该和引擎的 vanilla/paper/fabric/forge 混名。
        XCTAssertEqual(GameMode.allCases.map(\.title), ["Client", "Server"])
        XCTAssertEqual(GameMode.client.rawValue, "client")
    }
}
