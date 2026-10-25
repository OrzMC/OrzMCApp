import XCTest
import OrzMCRemoteHosting

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

@MainActor
final class RemoteStatusCenterTests: XCTestCase {

    func testPublishOnlyEmitsOnRealChange() async {
        let model = ExarotonServerModel()
        var iterator = model.statusEvents().makeAsyncIterator()

        model.publishStatus(.STARTING, for: "srv", source: .webSocket)
        let first = await iterator.next()
        XCTAssertEqual(first?.status.state, .starting)
        XCTAssertEqual(first?.status.serverStatus, .STARTING, "原始状态码要保留")
        XCTAssertNil(first?.previous)
        XCTAssertEqual(first?.source, .webSocket)
        XCTAssertFalse(first?.isChange ?? true, "第一次观测不是「变化」")

        let versionAfterFirst = model.statusVersion
        model.publishStatus(.STARTING, for: "srv", source: .polling)   // 重复 → 不发事件
        XCTAssertEqual(model.statusVersion, versionAfterFirst)

        model.publishStatus(.ONLINE, for: "srv", source: .polling)
        let second = await iterator.next()
        XCTAssertEqual(second?.previous?.serverStatus, .STARTING)
        XCTAssertEqual(second?.status.serverStatus, .ONLINE)
        XCTAssertEqual(second?.source, .polling)
        XCTAssertEqual(model.liveStatuses["srv"], .ONLINE)
        XCTAssertGreaterThan(model.statusVersion, versionAfterFirst)
    }

    /// 两路来源先后到达时，快照以"最后一次"为准，且不会互相打架。
    func testWebSocketAndPollingShareOneSnapshot() {
        let model = ExarotonServerModel()
        model.publishStatus(.LOADING, for: "srv", source: .webSocket)
        model.publishStatus(.ONLINE, for: "srv", source: .polling)
        XCTAssertEqual(model.effectiveStatus(for: Self.server(status: .OFFLINE)), .ONLINE)
        XCTAssertEqual(model.statusCenter.lastSource(for: model.instanceID("srv")), .polling)
    }

    /// 换账号时清空状态：旧账号的状态不能漂到新账号的列表上。
    func testResetRemoteStatusClearsSnapshot() {
        let model = ExarotonServerModel()
        model.publishStatus(.ONLINE, for: "srv", source: .webSocket)
        let version = model.statusVersion

        model.resetRemoteStatus()

        XCTAssertNil(model.statusCenter.status(for: model.instanceID("srv")))
        XCTAssertTrue(model.liveStatuses.isEmpty)
        XCTAssertGreaterThan(model.statusVersion, version, "界面要能感知到清空")
    }

    private static func server(status: ServerStatus) -> ExarotonServer {
        .init(id: "srv", name: "s", address: nil, motd: nil,
              status: .init(rawValue: status.rawValue), host: "h", port: 25565,
              players: .init(max: 20, count: 0, list: []), software: nil, shared: false)
    }
}

