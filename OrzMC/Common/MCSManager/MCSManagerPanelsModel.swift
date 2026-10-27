//
//  MCSManagerPanelsModel.swift
//  OrzMC
//
//  P2-7 第 4 步：**多个** MCSManager 面板的聚合（增 / 改 / 删 + 每面板一份模型）。
//
//  为什么一个面板一个 `MCSManagerModel`：轮询节律、状态中心都是"账号级"的，
//  两个面板各跑各的，删掉一个不会影响另一个的轮询（维护者的验收口径）。
//

import Foundation
import MCSMAPI
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

    /// 最近一次保存面板的校验错误（界面就地展示，不弹全局框）。
    var lastValidationError: String?

    @ObservationIgnored
    private let makeAPI: @Sendable (URL, String) -> any MCSManagerPanelAPI

    @ObservationIgnored
    private let store: any MCSManagerCredentialStore

    /// 仅 DEBUG 的界面验收：`ORZMC_DEMO_MCSM_FAKE=1` 时用内存里的假面板，不碰 Keychain/网络。
    @ObservationIgnored
    private var isDemo = false

    init(
        store: any MCSManagerCredentialStore = KeychainCredentialStore(),
        makeAPI: @escaping @Sendable (URL, String) -> any MCSManagerPanelAPI = { url, apiKey in
            MCSManagerAPIClient(serverURL: url, apiKey: apiKey)
        }
    ) {
        self.store = store
        self.makeAPI = makeAPI
        #if DEBUG
        if ProcessInfo.processInfo.environment["ORZMC_DEMO_MCSM_FAKE"] == "1" {
            isDemo = true
            installDemoData()
            return
        }
        #endif
        panels = store.panels()
        rebuildModels()
    }

    // MARK: - 面板增删改

    /// 添加面板；地址/Key 非法时返回 false，原因在 `lastValidationError`。
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
        guard !panels.contains(where: { $0.url == panel.url && $0.label == panel.label }) else {
            lastValidationError = String(localized: "This panel is already added.")
            return false
        }
        lastValidationError = nil

        panels.append(panel)
        if !isDemo {
            store.savePanels(panels)
            store.saveAPIKey(trimmedKey, for: panel.id)
        }
        rebuildModels()
        return true
    }

    /// 编辑面板（地址/名称/Key）。**`apiKey` 留空 = 不改 Key**（界面上只换地址时不用重新粘 key）。
    @discardableResult
    func updatePanel(id: UUID, label: String, rawURL: String, apiKey: String) -> Bool {
        guard let index = panels.firstIndex(where: { $0.id == id }) else { return false }
        guard let updated = MCSManagerPanel.make(id: id, label: label, rawURL: rawURL) else {
            lastValidationError = String(localized: "The panel address is not valid.")
            return false
        }
        guard !panels.contains(where: { $0.id != id && $0.url == updated.url && $0.label == updated.label }) else {
            lastValidationError = String(localized: "This panel is already added.")
            return false
        }
        lastValidationError = nil

        panels[index] = updated
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !isDemo {
            store.savePanels(panels)
            if !trimmedKey.isEmpty {
                store.saveAPIKey(trimmedKey, for: id)
            }
        }
        rebuildModels()
        // 地址可能变了：清掉旧快照，避免旧节点的实例挂在"同一个面板"下。
        models[id]?.setPanel(updated)
        return true
    }

    /// 删除面板：面板配置、Keychain 里的 key、模型与状态全部清掉。
    func removePanel(id: UUID) {
        panels.removeAll { $0.id == id }
        models[id]?.stopBackgroundRefresh()
        models[id] = nil
        if !isDemo {
            store.savePanels(panels)
            store.removeAPIKey(for: id)
        }
    }

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

    // MARK: - 连接自检（添加/编辑面板时的"测试连接"）

    /// 「测试连接」的结果。
    ///
    /// 成功时返回**结构化**信息（角色 + 名下实例数），文案由界面拼 —— 这样单测不依赖运行语言。
    enum ConnectionCheck: Equatable {
        case connected(role: Role, instanceCount: Int)
        case failed(String)
    }

    enum Role: Equatable {
        case administrator
        case user

        var localizedName: String {
            switch self {
            case .administrator: return String(localized: "administrator")
            case .user: return String(localized: "user")
            }
        }
    }

    /// 用**还没保存**的地址 + Key 打一次面板，返回给用户看的一句话。
    ///
    /// 走 `GET /api/auth`（普通用户/管理员都能用），顺带把角色和实例数报出来 ——
    /// 比"保存后等 20 秒看有没有实例"直观。
    func verifyConnection(rawURL: String, apiKey: String, panelID: UUID?) async -> ConnectionCheck {
        guard let url = MCSManagerPanel.normalizedURL(from: rawURL) else {
            return .failed(String(localized: "The panel address is not valid."))
        }
        let trimmedKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        // 编辑时留空 = 用已保存的 Key。
        let key = trimmedKey.isEmpty ? (panelID.flatMap { store.apiKey(for: $0) } ?? "") : trimmedKey
        guard !key.isEmpty else {
            return .failed(String(localized: "The API key is empty."))
        }

        do {
            let user = try await makeAPI(url, key).currentUser(advancedInstances: false)
            let role: Role = if let permission = user.permission, permission < MCSManagerRole.admin {
                .user
            } else {
                .administrator
            }
            return .connected(role: role, instanceCount: user.instances.count)
        } catch {
            return .failed(
                MCSManagerErrorText.describe(error)
                    ?? String(localized: "The panel did not answer as expected. Try again later.")
            )
        }
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
                apiKeyProvider: { [store] id in store.apiKey(for: id) }
            )
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

    /// 演示模式也支持动作（否则验收时按钮全是灰的）。
    func perform(_ action: RemoteServerAction, daemonID: String, instanceUUID: String) async throws {}

    func sendCommand(_ command: String, daemonID: String, instanceUUID: String) async throws {}

    func outputLog(daemonID: String, instanceUUID: String, tailSize: Int?) async throws -> String {
        """
        [12:00:00] [Server thread/INFO]: 演示面板的控制台输出
        [12:00:01] [Server thread/INFO]: 这一行用来验收控制台渲染
        """
    }

    /// 演示面板**不给**实时流通道（`nil`）→ 界面自动走轮询，正好把回退路径也验收掉。
    func streamChannel(daemonID: String, instanceUUID: String) async throws -> MCSMStreamChannel? {
        nil
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
