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

// MARK: - 状态中心（WS + HTTP 统一入口）

/// WS 与 HTTP 不是二选一：WS 安静了就必须靠轮询兜底。
/// 之前用 `isLive`（含 `readyServerID`）判断，WS 掉线后 `readyServerID` 不清空 →
/// 轮询被永久跳过 → 状态卡死（真机反馈「一直停在加载中」）。
final class RemoteStatusRefreshPolicyTests2: XCTestCase {

    private let now = Date()

    private func should(
        hasToken: Bool = true,
        isAppActive: Bool = true,
        wsActivity: TimeInterval? = nil,
        finished: TimeInterval? = nil,
        started: TimeInterval? = nil,
        isLoading: Bool = false
    ) -> Bool {
        RemoteStatusRefreshPolicy.shouldRefresh(
            hasToken: hasToken,
            isAppActive: isAppActive,
            lastWebSocketActivity: wsActivity.map { now.addingTimeInterval(-$0) },
            lastRefreshFinished: finished.map { now.addingTimeInterval(-$0) },
            refreshStartedAt: started.map { now.addingTimeInterval(-$0) },
            isLoading: isLoading,
            now: now
        )
    }

    func testPollsWhenWebSocketIsSilent() {
        // WS 30 秒前还有消息 → 该它了；再过 5 秒就静默超时
        XCTAssertFalse(should(wsActivity: 10, finished: 30))
        XCTAssertTrue(should(wsActivity: 40, finished: 30), "WS 静默超过 30 秒应交给轮询")
    }

    func testPollsWhenNeverConnected() {
        XCTAssertTrue(should(wsActivity: nil, finished: nil))
    }

    func testRespectsMinimumInterval() {
        XCTAssertFalse(should(finished: 3), "10 秒内不重复拉")
        XCTAssertTrue(should(finished: 12))
    }

    func testHandlesStuckRefresh() {
        XCTAssertFalse(should(started: 5, isLoading: true), "在途时等它")
        XCTAssertTrue(should(started: 40, isLoading: true), "卡住超过 25 秒允许重来")
    }

    func testSkipsInBackgroundOrWithoutToken() {
        XCTAssertFalse(should(isAppActive: false))
        XCTAssertFalse(should(hasToken: false))
    }
}

@MainActor
final class RemoteStatusCenterTests: XCTestCase {

    func testPublishOnlyEmitsOnRealChange() async {
        let model = ExarotonServerModel()
        var iterator = model.statusEvents().makeAsyncIterator()

        model.publishStatus(.STARTING, for: "srv", source: .webSocket)
        let first = await iterator.next()
        XCTAssertEqual(first?.status, .STARTING)
        XCTAssertNil(first?.previous)
        XCTAssertEqual(first?.source, .webSocket)

        model.publishStatus(.STARTING, for: "srv", source: .polling)   // 重复 → 不发事件
        model.publishStatus(.ONLINE, for: "srv", source: .polling)
        let second = await iterator.next()
        XCTAssertEqual(second?.previous, .STARTING)
        XCTAssertEqual(second?.status, .ONLINE)
        XCTAssertEqual(second?.source, .polling)
        XCTAssertEqual(model.liveStatuses["srv"], .ONLINE)
    }

    /// 两路来源先后到达时，快照以"最后一次"为准，且不会互相打架。
    func testWebSocketAndPollingShareOneSnapshot() {
        let model = ExarotonServerModel()
        model.publishStatus(.LOADING, for: "srv", source: .webSocket)
        model.publishStatus(.ONLINE, for: "srv", source: .polling)
        XCTAssertEqual(model.effectiveStatus(for: Self.server(status: .OFFLINE)), .ONLINE)
        XCTAssertEqual(model.lastStatusSource["srv"], .polling)
    }

    private static func server(status: ServerStatus) -> ExarotonServer {
        .init(id: "srv", name: "s", address: nil, motd: nil,
              status: .init(rawValue: status.rawValue), host: "h", port: 25565,
              players: .init(max: 20, count: 0, list: []), software: nil, shared: false)
    }
}

