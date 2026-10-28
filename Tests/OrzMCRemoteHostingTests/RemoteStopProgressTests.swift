import XCTest

@testable import OrzMCRemoteHosting

/// 「停止等了多久 / 该不该建议强杀」的判定（B2）。
///
/// 阈值是行为约定：改它等于改用户看到的提示时机，所以要连测试一起改。
final class RemoteStopProgressTests: XCTestCase {
    func testLevelsByElapsed() {
        XCTAssertEqual(RemoteStopProgress(elapsed: 0).level, .normal)
        XCTAssertEqual(RemoteStopProgress(elapsed: 29.9).level, .normal)
        XCTAssertEqual(RemoteStopProgress(elapsed: 30).level, .slow)
        XCTAssertEqual(RemoteStopProgress(elapsed: 59.9).level, .slow)
        XCTAssertEqual(RemoteStopProgress(elapsed: 60).level, .stalled)
        XCTAssertEqual(RemoteStopProgress(elapsed: 600).level, .stalled)
    }

    func testSuggestsForceStopOnlyWhenSlowOrStalled() {
        XCTAssertFalse(RemoteStopProgress(elapsed: 5).suggestsForceStop)
        XCTAssertTrue(RemoteStopProgress(elapsed: 30).suggestsForceStop)
        XCTAssertTrue(RemoteStopProgress(elapsed: 120).suggestsForceStop)
    }

    /// 时钟回拨 / "未来时间"不能显示成负数秒。
    func testNegativeElapsedClampsToZero() {
        let progress = RemoteStopProgress(elapsed: -12)
        XCTAssertEqual(progress.elapsed, 0)
        XCTAssertEqual(progress.seconds, 0)
        XCTAssertEqual(progress.level, .normal)
    }

    func testSinceDate() {
        let start = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(RemoteStopProgress(since: start, now: start.addingTimeInterval(42)).seconds, 42)
        XCTAssertEqual(RemoteStopProgress(since: start, now: start.addingTimeInterval(42)).level, .slow)
    }
}
