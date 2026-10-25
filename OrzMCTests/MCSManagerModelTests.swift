import XCTest
import OrzMCRemoteHosting

@testable import OrzMC

/// 假面板（`MCSManagerPanelAPI`）：不发网络请求，按配置回数据 / 抛错，并记录询问过的节点。
private actor FakePanelAPI: MCSManagerPanelAPI {

    private(set) var calls: [String] = []

    private let daemonsResult: Result<[MCSManagerDaemon], Error>
    private let pageResult: Result<MCSManagerInstancePage, Error>

    init(
        daemons: [MCSManagerDaemon] = [],
        page: MCSManagerInstancePage = .init(instances: [], maxPage: nil)
    ) {
        daemonsResult = .success(daemons)
        pageResult = .success(page)
    }

    /// 面板拒绝 / 连不上：所有请求都失败。
    init(failing error: Error) {
        daemonsResult = .failure(error)
        pageResult = .failure(error)
    }

    func daemons() async throws -> [MCSManagerDaemon] {
        calls.append("daemons")
        return try daemonsResult.get()
    }

    func instances(daemonID: String, page: Int, pageSize: Int) async throws -> MCSManagerInstancePage {
        calls.append("instances:\(daemonID):\(page)")
        return try pageResult.get()
    }
}

private func instance(
    _ uuid: String,
    daemon: String = "d1",
    nickname: String = "实例",
    status: Int = 3,
    address: String? = nil
) -> MCSManagerInstance {
    MCSManagerInstance(
        daemonID: daemon,
        instanceUUID: uuid,
        nickname: nickname,
        status: MCSManagerInstanceState(rawValue: status),
        address: address,
        players: nil
    )
}

/// MCSManager 只读适配（P2-7 第 4 步）。
@MainActor
final class MCSManagerModelTests: XCTestCase {

    private let panel = MCSManagerPanel(label: "自建面板", url: URL(string: "https://panel.example.com")!)

    private func makeModel(
        api: FakePanelAPI,
        apiKey: String = "test-key"
    ) -> MCSManagerModel {
        MCSManagerModel(
            panel: panel,
            makeAPI: { _, _ in api },
            apiKeyProvider: { _ in apiKey }
        )
    }

    // MARK: - 拉取

    func testReloadListsInstancesFromEveryAvailableDaemon() async {
        let api = FakePanelAPI(
            daemons: [
                .init(uuid: "d1", available: true),
                .init(uuid: "d2", available: true),
                .init(uuid: "d3", available: false),
            ],
            page: .init(instances: [instance("i1", nickname: "主世界"), instance("i2", nickname: "创造服", status: 0)], maxPage: 1)
        )
        let model = makeModel(api: api)

        await model.reload()

        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(model.hasLoaded)
        let calls = await api.calls
        XCTAssertFalse(calls.contains("instances:d3:1"), "掉线节点不去问实例")
        XCTAssertEqual(model.instances.count, 4, "两个可用节点 × 各 2 台实例")
        XCTAssertEqual(model.instances.first { $0.instanceUUID == "i1" }?.status, MCSManagerInstanceState.running)
    }

    /// 面板每页最多 50 条，`maxPage > 1` 时要继续翻页。
    func testReloadFollowsPagination() async {
        let api = FakePanelAPI(
            daemons: [.init(uuid: "d1", available: true)],
            page: .init(instances: [instance("i1")], maxPage: 3)
        )
        let model = makeModel(api: api)

        await model.reload()

        let calls = await api.calls
        XCTAssertEqual(calls.filter { $0.hasPrefix("instances:d1:") }, ["instances:d1:1", "instances:d1:2", "instances:d1:3"])
        XCTAssertEqual(model.instances.count, 3)
    }

    func testReloadPublishesStatusesIntoCenter() async {
        let api = FakePanelAPI(
            daemons: [.init(uuid: "d1", available: true)],
            page: .init(instances: [instance("i1", nickname: "在线", status: 3), instance("i2", status: 0)], maxPage: 1)
        )
        let model = makeModel(api: api)

        await model.reload()

        let online = model.instanceID("d1/i1")
        XCTAssertEqual(model.statusCenter.status(for: online)?.state, RemoteServerState.online)
        XCTAssertEqual(model.statusCenter.status(for: online)?.rawStatus, 3)
        XCTAssertEqual(model.statusCenter.lastSource(for: online), RemoteStatusSource.polling)
        XCTAssertEqual(model.statusCenter.status(for: model.instanceID("d1/i2"))?.state, RemoteServerState.offline)
        // 状态中心只在真变化时递增版本（重复 push 不会）
    }

    /// 面板 403（key 失效 / 没开 API Key 功能）→ 一句人话，而不是 NSError 转储。
    func testUnauthorizedSurfacesReadableError() async {
        let api = FakePanelAPI(failing: MCSManagerModelError.unauthorized)
        let model = makeModel(api: api)

        await model.reload()

        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(
            model.errorMessage,
            MCSManagerErrorText.describe(MCSManagerModelError.unauthorized)
        )
        XCTAssertFalse(model.hasLoaded)
        XCTAssertTrue(model.instances.isEmpty)
    }

    /// 没有 key 就不发请求（也没必要打扰用户）。
    func testReloadWithoutAPIKeyDoesNothing() async {
        let api = FakePanelAPI(daemons: [.init(uuid: "d1", available: true)])
        let model = makeModel(api: api, apiKey: "")

        await model.reload()

        XCTAssertFalse(model.hasCredentials)
        let calls = await api.calls
        XCTAssertTrue(calls.isEmpty)
    }

    /// 换面板（换账号）要清掉旧快照，旧面板的状态不能漂到新面板上。
    func testSetPanelClearsSnapshot() async {
        let api = FakePanelAPI(
            daemons: [.init(uuid: "d1", available: true)],
            page: .init(instances: [instance("i1")], maxPage: 1)
        )
        let model = makeModel(api: api)
        await model.reload()
        XCTAssertFalse(model.instances.isEmpty)

        model.setPanel(nil)

        XCTAssertTrue(model.instances.isEmpty)
        XCTAssertNil(model.statusCenter.status(for: model.instanceID("d1/i1")))
        XCTAssertFalse(model.hasLoaded)
    }

    // MARK: - 映射

    func testInstanceStateMapping() {
        XCTAssertEqual(MCSManagerInstanceState(rawValue: -1), .busy)
        XCTAssertEqual(MCSManagerInstanceState(rawValue: 0), .stopped)
        XCTAssertEqual(MCSManagerInstanceState(rawValue: 1), .stopping)
        XCTAssertEqual(MCSManagerInstanceState(rawValue: 2), .starting)
        XCTAssertEqual(MCSManagerInstanceState(rawValue: 3), .running)
        XCTAssertEqual(MCSManagerInstanceState(rawValue: 9), .unknown(9))

        XCTAssertEqual(MCSManagerInstanceState.running.remoteState, .online)
        XCTAssertEqual(MCSManagerInstanceState.stopped.remoteState, .offline)
        XCTAssertEqual(MCSManagerInstanceState.starting.remoteState, .starting)
        XCTAssertEqual(MCSManagerInstanceState.stopping.remoteState, .stopping)
        // busy = 正在处理上一条指令，底层状态不明 → 过渡态（禁用动作）
        XCTAssertEqual(MCSManagerInstanceState.busy.remoteState, .unknown)
        XCTAssertEqual(MCSManagerInstanceState.unknown(9).remoteState, .unknown)

        // 原始码要能原样带回去（界面区分细节 / 排查用）
        for raw in [-1, 0, 1, 2, 3, 9] {
            XCTAssertEqual(MCSManagerInstanceState(rawValue: raw).rawValue, raw)
        }
    }

    func testInstanceSummariesUseProviderScopedIDs() async {
        let api = FakePanelAPI(
            daemons: [.init(uuid: "d1", available: true)],
            page: .init(
                instances: [
                    instance("i1", nickname: "主世界", status: 3, address: "play.example.com:25565"),
                    instance("i2", nickname: "创造服", status: 0),
                ],
                maxPage: 1
            )
        )
        let model = makeModel(api: api)
        await model.reload()

        let summaries = model.instanceSummaries()
        XCTAssertEqual(summaries.count, 2)
        let first = summaries.first { $0.id.rawValue == "d1/i1" }
        XCTAssertEqual(first?.provider, .mcsmanager)
        XCTAssertEqual(first?.name, "主世界")
        XCTAssertEqual(first?.address, "play.example.com:25565")
        XCTAssertEqual(first?.state, RemoteServerState.online)
        // 没配 pingConfig 的实例没有地址（不是空串）
        XCTAssertNil(summaries.first { $0.id.rawValue == "d1/i2" }?.address)
    }

    /// 同一个实例 id 在两家供应商下互不影响（键是 `RemoteInstanceID`）。
    func testInstanceIDsAreNamespacedByProvider() {
        let model = makeModel(api: FakePanelAPI())
        XCTAssertNotEqual(
            model.instanceID("d1/i1"),
            RemoteInstanceID(provider: .exaroton, rawValue: "d1/i1")
        )
    }

    // MARK: - 供应商抽象层

    func testHostingProviderIsReadOnlyForNow() async {
        let api = FakePanelAPI(
            daemons: [.init(uuid: "d1", available: true)],
            page: .init(instances: [instance("i1")], maxPage: 1)
        )
        let model = makeModel(api: api)
        await model.reload()
        let provider = model.hostingProvider

        XCTAssertEqual(provider.kind, .mcsmanager)
        let listed = try? await provider.listInstances()
        XCTAssertEqual(listed?.count, 1)

        do {
            try await provider.perform(.start, on: model.instanceID("d1/i1"))
            XCTFail("只读接入阶段不该假装动作成功")
        } catch {
            XCTAssertEqual(error as? RemoteHostingError, .actionNotSupported(.start))
        }
    }

    func testHostingProviderRejectsForeignInstance() async {
        let model = makeModel(api: FakePanelAPI())
        do {
            try await model.hostingProvider.perform(
                .stop,
                on: RemoteInstanceID(provider: .exaroton, rawValue: "srv")
            )
            XCTFail("应该抛 wrongProvider")
        } catch {
            XCTAssertEqual(
                error as? RemoteHostingError,
                .wrongProvider(expected: .mcsmanager, actual: .exaroton)
            )
        }
    }

    // MARK: - 面板地址

    func testPanelURLNormalization() {
        XCTAssertEqual(
            MCSManagerPanel.normalizedURL(from: "panel.example.com")?.absoluteString,
            "https://panel.example.com"
        )
        XCTAssertEqual(
            MCSManagerPanel.normalizedURL(from: "  https://panel.example.com/sub/  ")?.absoluteString,
            "https://panel.example.com/sub"
        )
        XCTAssertEqual(
            MCSManagerPanel.normalizedURL(from: "http://192.168.1.10:23333")?.absoluteString,
            "http://192.168.1.10:23333"
        )
        XCTAssertNil(MCSManagerPanel.normalizedURL(from: "   "))
        XCTAssertNil(MCSManagerPanel.normalizedURL(from: "file:///etc/passwd"))
    }

    func testPanelFallsBackToHostAsLabel() {
        let panel = MCSManagerPanel.make(label: "  ", rawURL: "https://panel.example.com/x")
        XCTAssertEqual(panel?.label, "panel.example.com")
        XCTAssertEqual(panel?.url.absoluteString, "https://panel.example.com/x")
    }
}
