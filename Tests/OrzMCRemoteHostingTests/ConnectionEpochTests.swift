import XCTest
@testable import OrzMCRemoteHosting

/// 连接代数：迟到回调必须被丢弃（离开详情后不再写回已清空的状态）。
final class ConnectionEpochTests: XCTestCase {
    func testInitialEpochIsAccepted() {
        let epoch = ConnectionEpoch()
        XCTAssertTrue(epoch.accepts(epoch.current))
    }

    func testAdvanceInvalidatesPreviousEpoch() {
        var epoch = ConnectionEpoch()
        let first = epoch.advance()
        XCTAssertTrue(epoch.accepts(first))

        let second = epoch.advance()
        XCTAssertNotEqual(first, second)
        XCTAssertFalse(epoch.accepts(first), "上一条连接的回调必须被拒绝")
        XCTAssertTrue(epoch.accepts(second))
    }

    func testClosingConnectionAlsoInvalidates() {
        var epoch = ConnectionEpoch()
        let open = epoch.advance()
        epoch.advance()   // stopConnect 也要前进一代
        XCTAssertFalse(epoch.accepts(open))
    }
}
