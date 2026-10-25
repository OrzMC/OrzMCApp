import XCTest
@testable import OrzMCRemoteHosting

/// 供应商无关的状态中心：唯一写入口 + 只在真变化时发事件。
@MainActor
final class RemoteStatusCenterTests: XCTestCase {

    private let srv = RemoteInstanceID(provider: .exaroton, rawValue: "srv")

    func testPublishOnlyEmitsOnRealChange() async {
        let center = RemoteStatusCenter()
        var iterator = center.events().makeAsyncIterator()

        XCTAssertTrue(center.publish(.init(state: .starting), for: srv, source: .webSocket))
        let first = await iterator.next()
        XCTAssertEqual(first?.instance, srv)
        XCTAssertEqual(first?.status.state, .starting)
        XCTAssertNil(first?.previous, "第一次观测没有 previous")
        XCTAssertEqual(first?.source, .webSocket)
        XCTAssertFalse(first?.isChange ?? true, "第一次观测不是「变化」")

        // 重复推送 → 不发事件、不递增版本
        let versionAfterFirst = center.version
        XCTAssertFalse(center.publish(.init(state: .starting), for: srv, source: .polling))
        XCTAssertEqual(center.version, versionAfterFirst)

        XCTAssertTrue(center.publish(.init(state: .online), for: srv, source: .polling))
        let second = await iterator.next()
        XCTAssertEqual(second?.previous?.state, .starting)
        XCTAssertEqual(second?.status.state, .online)
        XCTAssertEqual(second?.source, .polling)
        XCTAssertTrue(second?.isChange ?? false)
        XCTAssertEqual(center.status(for: srv)?.state, .online)
        XCTAssertEqual(center.lastSource(for: srv), .polling)
    }

    /// 同一个原始 id、不同供应商互不影响（实例键必须是 `RemoteInstanceID`）。
    func testInstancesAreIsolatedPerProvider() {
        let center = RemoteStatusCenter()
        let exaroton = RemoteInstanceID(provider: .exaroton, rawValue: "42")
        let mcsmanager = RemoteInstanceID(provider: .mcsmanager, rawValue: "42")

        center.publish(.init(state: .online), for: exaroton, source: .webSocket)

        XCTAssertEqual(center.status(for: exaroton)?.state, .online)
        XCTAssertNil(center.status(for: mcsmanager))
        XCTAssertEqual(center.allStatuses.count, 1)
    }

    /// 原始状态码要保留：界面靠它区分「启动中 / 加载中 / 准备中」。
    func testRawStatusIsPreserved() {
        let center = RemoteStatusCenter()
        center.publish(.init(state: .starting, rawStatus: 6), for: srv, source: .webSocket)

        XCTAssertEqual(center.status(for: srv), RemoteInstanceStatus(state: .starting, rawStatus: 6))
        XCTAssertNotEqual(
            center.status(for: srv),
            RemoteInstanceStatus(state: .starting, rawStatus: 10),
            "原始码不同就是不同状态（会再发一次事件）"
        )
    }

    func testMultipleSubscribersGetTheSameEvent() async {
        let center = RemoteStatusCenter()
        var a = center.events().makeAsyncIterator()
        var b = center.events().makeAsyncIterator()

        center.publish(.init(state: .online), for: srv, source: .webSocket)

        let eventA = await a.next()
        let eventB = await b.next()
        XCTAssertEqual(eventA, eventB)
    }

    func testForgetAndResetClearSnapshots() {
        let center = RemoteStatusCenter()
        let other = RemoteInstanceID(provider: .exaroton, rawValue: "other")
        center.publish(.init(state: .online), for: srv, source: .webSocket)
        center.publish(.init(state: .offline), for: other, source: .polling)
        let version = center.version

        center.forget(srv)
        XCTAssertNil(center.status(for: srv))
        XCTAssertNil(center.lastSource(for: srv))
        XCTAssertEqual(center.version, version, "实例消失不是「它变了个状态」")
        XCTAssertEqual(center.allStatuses.count, 1)

        center.reset()
        XCTAssertTrue(center.allStatuses.isEmpty)
        XCTAssertNil(center.lastWebSocketActivityAt)
        XCTAssertNil(center.lastRefreshStartedAt)
        XCTAssertNil(center.lastRefreshFinishedAt)
    }
}

/// 刷新节律：WS 安静 30 秒才轮到轮询（**P2-7 红线，判据不可改**）。
@MainActor
final class RemoteStatusRefreshPolicyTests: XCTestCase {

    private let now = Date()

    private func center(
        wsActivity: TimeInterval? = nil,
        finished: TimeInterval? = nil,
        started: TimeInterval? = nil
    ) -> RemoteStatusCenter {
        let center = RemoteStatusCenter()
        if let wsActivity {
            center.noteWebSocketActivity(at: now.addingTimeInterval(-wsActivity))
        }
        if let started { center.beginRefresh(at: now.addingTimeInterval(-started)) }
        if let finished { center.finishRefresh(at: now.addingTimeInterval(-finished)) }
        return center
    }

    private func should(
        wsActivity: TimeInterval? = nil,
        finished: TimeInterval? = nil,
        started: TimeInterval? = nil,
        hasCredentials: Bool = true,
        isAppActive: Bool = true,
        isLoading: Bool = false
    ) -> Bool {
        center(wsActivity: wsActivity, finished: finished, started: started).shouldRefresh(
            hasCredentials: hasCredentials,
            isAppActive: isAppActive,
            isLoading: isLoading,
            now: now
        )
    }

    func testPollsWhenWebSocketIsSilent() {
        // WS 10 秒前还有消息 → 还该等它
        XCTAssertFalse(should(wsActivity: 10, finished: 30))
        // WS 静默超过 30 秒 → 轮询接管
        XCTAssertTrue(should(wsActivity: 40, finished: 30))
    }

    func testPollsWhenNeverConnected() {
        XCTAssertTrue(should(wsActivity: nil, finished: nil))
    }

    func testPollsWhenProviderHasNoWebSocket() {
        // MCSM 没有 WS：从不记 activity，也只按最小间隔轮询
        XCTAssertTrue(should(finished: 30))
        XCTAssertFalse(should(finished: 3))
    }

    func testRespectsMinimumInterval() {
        XCTAssertFalse(should(finished: 3), "10 秒内不重复拉")
        XCTAssertTrue(should(finished: 12))
    }

    func testHandlesStuckRefresh() {
        XCTAssertFalse(should(started: 5, isLoading: true), "在途时等它")
        XCTAssertTrue(should(started: 40, isLoading: true), "卡住超过 25 秒允许重来")
        XCTAssertTrue(
            center(started: 30).shouldRefresh(hasCredentials: true, isAppActive: true, isLoading: false),
            "不在途时 started 不参与判断（只看 finished 的最小间隔）"
        )
    }

    func testSkipsInBackgroundOrWithoutCredentials() {
        XCTAssertFalse(should(isAppActive: false))
        XCTAssertFalse(should(hasCredentials: false))
    }

    /// 纯函数本身：不依赖状态中心的那份（供不需要中心的调用方使用）。
    func testPurePolicyStillAvailable() {
        XCTAssertTrue(
            RemoteStatusRefreshPolicy.shouldRefresh(
                hasToken: true,
                isAppActive: true,
                lastWebSocketActivity: nil,
                lastRefreshFinished: nil,
                refreshStartedAt: nil,
                isLoading: false,
                now: now
            )
        )
        XCTAssertEqual(RemoteStatusRefreshPolicy.webSocketSilentAfter, 30)
    }
}
