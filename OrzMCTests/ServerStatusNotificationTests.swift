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

// MARK: - 列表与推送状态一致性

/// 之前只有详情页消费 WebSocket 的状态推送，列表读 HTTP 快照 → 两边不一致：
/// 服务器已经在线/正在启动，列表还显示「离线」；一进详情页状态"跳"成在线，
/// 看起来像 App 自己把服务器启动了。`effectiveStatus(for:)` 统一了取值来源。
@MainActor
final class RemoteStatusConsistencyTests: XCTestCase {

    private func makeServer(status: ServerStatus) -> ExarotonServer {
        .init(
            id: "testsrv",
            name: "测试服",
            address: nil,
            motd: nil,
            status: .init(rawValue: status.rawValue),
            host: "example.com",
            port: 25565,
            players: .init(max: 20, count: 0, list: []),
            software: nil,
            shared: false
        )
    }

    func testEffectiveStatusPrefersPushedValue() {
        let model = ExarotonServerModel()
        let server = makeServer(status: .OFFLINE)
        XCTAssertEqual(model.effectiveStatus(for: server), .OFFLINE, "没有推送时用 HTTP 快照")

        model.liveStatuses[server.id ?? ""] = .STARTING
        XCTAssertEqual(model.effectiveStatus(for: server), .STARTING, "推送值优先于快照")
    }

    func testEffectiveStatusFallsBackWhenNoPush() {
        let model = ExarotonServerModel()
        let server = makeServer(status: .ONLINE)
        XCTAssertEqual(model.effectiveStatus(for: server), .ONLINE)
    }
}

// MARK: - 后台轮询策略

/// 状态必须能随时间自己追上服务端。轮询挂在**模型**上（不随视图生命周期中断），
/// 这几条守住"什么时候该拉、什么时候别白拉"。
final class RemoteStatusRefreshPolicyTests: XCTestCase {

    func testRefreshWhenNothingElseProvidesUpdates() {
        XCTAssertTrue(RemoteStatusRefreshPolicy.shouldRefresh(
            hasToken: true, isWebSocketLive: false, isAppActive: true, isLoading: false
        ))
    }

    func testSkipWhileWebSocketFeedsStatus() {
        XCTAssertFalse(RemoteStatusRefreshPolicy.shouldRefresh(
            hasToken: true, isWebSocketLive: true, isAppActive: true, isLoading: false
        ))
    }

    func testSkipWithoutToken() {
        XCTAssertFalse(RemoteStatusRefreshPolicy.shouldRefresh(
            hasToken: false, isWebSocketLive: false, isAppActive: true, isLoading: false
        ))
    }

    func testSkipInBackgroundAndWhileLoading() {
        XCTAssertFalse(RemoteStatusRefreshPolicy.shouldRefresh(
            hasToken: true, isWebSocketLive: false, isAppActive: false, isLoading: false
        ))
        XCTAssertFalse(RemoteStatusRefreshPolicy.shouldRefresh(
            hasToken: true, isWebSocketLive: false, isAppActive: true, isLoading: true
        ))
    }
}
