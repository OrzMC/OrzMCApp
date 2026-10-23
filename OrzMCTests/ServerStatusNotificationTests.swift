import XCTest

@testable import OrzMC

/// 状态变化检测：**只在真的翻转时**报事件，第一次观测不报。
final class ServerStatusNotificationTests: XCTestCase {

    func testFirstObservationNeverReports() {
        XCTAssertNil(ServerStatusChangeDetector.event(isKnown: false, wasOnline: false, isOnline: true))
        XCTAssertNil(ServerStatusChangeDetector.event(isKnown: false, wasOnline: false, isOnline: false))
    }

    func testOnlineToOffline() {
        XCTAssertEqual(
            ServerStatusChangeDetector.event(isKnown: true, wasOnline: true, isOnline: false),
            .wentOffline
        )
    }

    func testOfflineToOnline() {
        XCTAssertEqual(
            ServerStatusChangeDetector.event(isKnown: true, wasOnline: false, isOnline: true),
            .wentOnline
        )
    }

    func testNoChangeReportsNothing() {
        XCTAssertNil(ServerStatusChangeDetector.event(isKnown: true, wasOnline: true, isOnline: true))
        XCTAssertNil(ServerStatusChangeDetector.event(isKnown: true, wasOnline: false, isOnline: false))
    }

    /// 事件标题是本地化键（至少在中文环境下不是空串）。
    func testEventTitlesAreLocalized() {
        XCTAssertFalse(ServerStatusEvent.wentOnline.title.isEmpty)
        XCTAssertFalse(ServerStatusEvent.wentOffline.title.isEmpty)
    }
}
