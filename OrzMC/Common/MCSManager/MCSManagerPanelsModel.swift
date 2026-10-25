//
//  MCSManagerPanelsModel.swift
//  OrzMC
//
//  P2-7 第 4 步：**多个** MCSManager 面板的聚合。
//
//  为什么一个面板一个 `MCSManagerModel`：WS/轮询节律/状态中心都是"账号级"的，
//  两个面板各跑各的，删掉一个不会影响另一个的轮询（维护者的验收口径）。
//

import Foundation
import OrzMCRemoteHosting

@MainActor
@Observable
final class MCSManagerPanelsModel {

    /// 已配置的面板（`UserDefaults`）。
    private(set) var panels: [MCSManagerPanel] = []

    /// 每个面板一份模型（各有一份状态中心）。
    @ObservationIgnored
    private(set) var models: [UUID: MCSManagerModel] = [:]

    /// App 是否在前台（由场景驱动）。后台时所有面板都停轮询。
    var isSceneActive = true {
        didSet { models.values.forEach { $0.isSceneActive = isSceneActive } }
    }

    @ObservationIgnored
    private let makeAPI: @Sendable (URL, String) -> any MCSManagerPanelAPI

    @ObservationIgnored
    private let apiKeyProvider: @Sendable (UUID) -> String?

    /// 仅 DEBUG 的界面验收：`ORZMC_DEMO_MCSM_FAKE=1` 时用内存里的假面板，不碰 Keychain/网络。
    @ObservationIgnored
    private var isDemo = false

    init(
        makeAPI: @escaping @Sendable (URL, String) -> any MCSManagerPanelAPI = { url, apiKey in
            MCSManagerAPIClient(serverURL: url, apiKey: apiKey)
        },
        apiKeyProvider: @escaping @Sendable (UUID) -> String? = { id in
            MCSManagerCredentials.apiKey(for: id)
        }
    ) {
        self.makeAPI = makeAPI
        self.apiKeyProvider = apiKeyProvider
        #if DEBUG
        if ProcessInfo.processInfo.environment["ORZMC_DEMO_MCSM_FAKE"] == "1" {
            isDemo = true
            installDemoData()
            return
        }
        #endif
        panels = MCSManagerCredentials.panels()
        rebuildModels()
    }

    // MARK: - 面板增删

    /// 添加面板；地址非法返回 false（界面据 `lastValidationError` 提示）。
    @discardableResult
    func addPanel(label: String, rawURL: String, apiKey: String) -> Bool {
        guard let panel = MCSManagerPanel.make(label: label, rawURL: rawURL) else {
            lastValidationError = String(localized: "The panel address is not valid.")
            return false
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedKey.isEmpty else {
            lastValidationError = String(localized: "The API key is empty.")
            return false
        }
        lastValidationError = nil

        panels.append(panel)
        if !isDemo {
            MCSManagerCredentials.save(panels)
            MCSManagerCredentials.saveAPIKey(trimmedKey, for: panel.id)
        }
        rebuildModels()
        return true
    }

    /// 删除面板：面板配置、Keychain 里的 key、模型与状态全部清掉。
    func removePanel(id: UUID) {
        panels.removeAll { $0.id == id }
        models[id]?.stopBackgroundRefresh()
        models[id] = nil
        if !isDemo {
            MCSManagerCredentials.save(panels)
            MCSManagerCredentials.removeAPIKey(for: id)
        }
    }

    /// 最近一次添加面板的校验错误（界面就地展示，不弹全局框）。
    var lastValidationError: String?

    // MARK: - 查询

    func model(for panelID: UUID) -> MCSManagerModel? {
        models[panelID]
    }

    func instances(of panelID: UUID) -> [MCSManagerInstance] {
        models[panelID]?.instances ?? []
    }

    /// 所有面板的实例摘要（供应商无关）——留给统一列表/分组用。
    func instanceSummaries() -> [RemoteInstanceSummary] {
        models.values.flatMap { $0.instanceSummaries() }
    }

    /// 按供应商分组（当前只有 mcsmanager 一组，exaroton 走自己的老界面）。
    var hostingGroups: [RemoteHostingGroup] {
        RemoteHostingGrouping.groups(from: instanceSummaries())
    }

    // MARK: - 拉取 / 轮询

    func reloadAll() async {
        for model in models.values {
            await model.reload()
        }
    }

    /// 每个面板各自的心跳循环（互不阻塞）。
    func start() {
        models.values.forEach { model in
            model.isSceneActive = isSceneActive
            model.startBackgroundRefresh()
        }
    }

    func stop() {
        models.values.forEach { $0.stopBackgroundRefresh() }
    }

    // MARK: - 内部

    private func rebuildModels() {
        var updated: [UUID: MCSManagerModel] = [:]
        for panel in panels {
            // 保留已有模型（避免换一次面板列表就把状态/订阅重建掉）。
            let model = models[panel.id] ?? MCSManagerModel(
                panel: panel,
                makeAPI: makeAPI,
                apiKeyProvider: apiKeyProvider
            )
            model.setPanel(panel)
            model.isSceneActive = isSceneActive
            updated[panel.id] = model
        }
        // 被删掉的面板停掉心跳，别让它在后台继续轮询。
        for (id, model) in models where updated[id] == nil {
            model.stopBackgroundRefresh()
        }
        models = updated
    }

    #if DEBUG
    /// 界面验收用的假面板（不碰 Keychain、不发网络请求）。
    private func installDemoData() {
        let panel = MCSManagerPanel(
            label: "演示面板",
            url: URL(string: "https://panel.example.com")!
        )
        let fake = MCSManagerDemoPanelAPI()
        panels = [panel]
        models = [
            panel.id: MCSManagerModel(
                panel: panel,
                makeAPI: { _, _ in fake },
                apiKeyProvider: { _ in "demo-key" }
            )
        ]
    }
    #endif
}

#if DEBUG
/// 假面板：两台实例（一在线一停止），点"刷新"状态会翻转一次，用来验收状态徽章。
actor MCSManagerDemoPanelAPI: MCSManagerPanelAPI {

    private var flip = false

    /// 演示面板按**普通用户**走（真机验收时维护者用的就是普通 key）。
    func currentUser(advancedInstances: Bool) async throws -> MCSManagerCurrentUser {
        MCSManagerCurrentUser(permission: 1, instances: instances(flipped: false))
    }

    func daemons() async throws -> [MCSManagerDaemon] {
        [MCSManagerDaemon(uuid: "demo-daemon", available: true)]
    }

    func instances(daemonID: String, page: Int, pageSize: Int) async throws -> MCSManagerInstancePage {
        flip.toggle()
        return MCSManagerInstancePage(instances: instances(flipped: flip), maxPage: 1)
    }

    private func instances(flipped: Bool) -> [MCSManagerInstance] {
        [
            MCSManagerInstance(
                daemonID: "demo-daemon",
                instanceUUID: "demo-1",
                nickname: "演示生存服",
                status: flipped ? .starting : .running,
                address: "play.example.com:25565",
                players: MCSManagerPlayers(current: 3, max: 20)
            ),
            MCSManagerInstance(
                daemonID: "demo-daemon",
                instanceUUID: "demo-2",
                nickname: "演示创造服",
                status: .stopped,
                address: nil,
                players: MCSManagerPlayers(current: 0, max: 20)
            ),
        ]
    }
}
#endif
