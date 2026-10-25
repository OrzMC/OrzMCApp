//
//  MCSManagerModel.swift
//  OrzMC
//
//  P2-7 第 4 步：app 侧的 MCSManager **只读**适配（列实例 + 轮询状态）。
//
//  与 exaroton 的差别（也是抽象层存在的意义）：
//    - 没有 WebSocket → 状态只能靠 HTTP 轮询；`RemoteStatusCenter.shouldRefresh` 在
//      "从未有 WS 消息"时自然退化成按最小间隔轮询，这里不用另写一套节律；
//    - 实例归属两级：面板 → 节点（daemon）→ 实例，所以实例 id 用 `daemonId/instanceUuid`。
//
//  凭据：面板地址在 `UserDefaults`、API Key 在 Keychain（见 `MCSManagerPanel.swift`）。
//

import Foundation

import OrzMCRemoteHosting

/// 面板给的实例状态码（`InstanceDetail.status`）。
enum MCSManagerInstanceState: Equatable, Sendable {
    case busy
    case stopped
    case stopping
    case starting
    case running
    /// 面板新增了没见过的码（宽容解码：不要让整条实例消失）。
    case unknown(Int)

    init(rawValue: Int) {
        switch rawValue {
        case -1: self = .busy
        case 0: self = .stopped
        case 1: self = .stopping
        case 2: self = .starting
        case 3: self = .running
        default: self = .unknown(rawValue)
        }
    }

    /// 原始状态码（写进 `RemoteInstanceStatus.rawStatus`，界面需要区分细节时用）。
    var rawValue: Int {
        switch self {
        case .busy: return -1
        case .stopped: return 0
        case .stopping: return 1
        case .starting: return 2
        case .running: return 3
        case .unknown(let raw): return raw
        }
    }

    /// 归一化成供应商无关状态（徽章 / 动作可用性只认它）。
    var remoteState: RemoteServerState {
        switch self {
        case .running: return .online
        case .stopped: return .offline
        case .starting: return .starting
        case .stopping: return .stopping
        // busy = 正在处理上一条指令；面板没说明底层状态 → 过渡态，按"未知"处理（禁用动作）。
        case .busy, .unknown: return .unknown
        }
    }
}

/// 玩家数（面板 `info`；列表端点也会给）。
struct MCSManagerPlayers: Equatable, Sendable {
    let current: Int?
    let max: Int?
}

/// 一条 MCSManager 实例（面板 → 节点 → 实例）。
struct MCSManagerInstance: Identifiable, Equatable, Sendable {
    let daemonID: String
    let instanceUUID: String
    let nickname: String
    let status: MCSManagerInstanceState
    /// 玩家连的地址（面板 `pingConfig`，没配就是 nil）。
    let address: String?
    let players: MCSManagerPlayers?

    /// 全局键：同一个 `instanceUuid` 在不同节点上（理论上）可能重复，带上 daemonId 才唯一。
    var id: String { "\(daemonID)/\(instanceUUID)" }
}

/// 面板级错误（文案由 `MCSManagerErrorText` 出）。
///
/// `panelMessage` 是**面板自己返回的那句话**（`{"status":403,"data":"密钥不正确"}` 里的 `data`）：
/// MCSManager 的 403 有好几种含义（密钥不正确 / API Key 功能已关闭 / 权限不足），
/// 面板已经把它说清楚了，界面直接转述比我们自己猜更准。
enum MCSManagerModelError: Error, Equatable {
    /// 403：API Key 失效 / 面板没开 API Key 功能 / 权限不足。
    case unauthorized(panelMessage: String?)
    /// 其它 HTTP 状态码（5xx 等）。
    case server(Int, panelMessage: String?)
}

@MainActor
@Observable
final class MCSManagerModel {

    // MARK: - 输入

    /// 当前面板（nil = 还没配置）。
    private(set) var panel: MCSManagerPanel?

    // MARK: - 只读快照

    /// 面板上的实例（列表/详情用）。
    private(set) var instances: [MCSManagerInstance] = []
    var errorMessage: String?
    var isLoading = false
    private(set) var hasLoaded = false

    /// 状态中心（一个面板一份）。键是 `RemoteInstanceID(.mcsmanager, "daemon/uuid")`。
    @ObservationIgnored
    let statusCenter = RemoteStatusCenter()

    // MARK: - 依赖

    /// 由 app 构造面板客户端（单测注入假实现，实现"零网络"且不碰 OpenAPI 类型）。
    @ObservationIgnored
    private let makeAPI: @Sendable (URL, String) -> any MCSManagerPanelAPI

    /// API Key 从哪来（默认 Keychain；单测注入固定值，避免碰钥匙串）。
    @ObservationIgnored
    private let apiKeyProvider: @Sendable (UUID) -> String?

    @ObservationIgnored
    private var backgroundRefreshTask: Task<Void, Never>?

    /// App 是否在前台（由场景驱动）。后台时不轮询。
    @ObservationIgnored
    var isSceneActive = true

    init(
        panel: MCSManagerPanel? = nil,
        makeAPI: @escaping @Sendable (URL, String) -> any MCSManagerPanelAPI = { url, apiKey in
            MCSManagerAPIClient(serverURL: url, apiKey: apiKey)
        },
        apiKeyProvider: @escaping @Sendable (UUID) -> String? = { id in
            MCSManagerCredentials.apiKey(for: id)
        }
    ) {
        self.panel = panel
        self.makeAPI = makeAPI
        self.apiKeyProvider = apiKeyProvider
    }

    // MARK: - 配置

    /// 换面板（换账号）：清空快照与状态中心，避免旧面板的状态漂过来。
    func setPanel(_ panel: MCSManagerPanel?) {
        guard panel != self.panel else { return }
        self.panel = panel
        instances = []
        hasLoaded = false
        errorMessage = nil
        statusCenter.reset()
        if panel == nil { stopBackgroundRefresh() }
    }

    var hasCredentials: Bool {
        guard let panel else { return false }
        return apiKeyProvider(panel.id)?.isEmpty == false
    }

    // MARK: - 拉取（只读）

    /// 拉一次：节点列表 → 每个可用节点上的实例（分页取全）→ 状态写进状态中心。
    func reload() async {
        guard let panel, !isLoading,
              let apiKey = apiKeyProvider(panel.id),
              !apiKey.isEmpty
        else { return }

        isLoading = true
        errorMessage = nil
        statusCenter.beginRefresh()
        defer {
            isLoading = false
            statusCenter.finishRefresh()
        }

        do {
            let api = makeAPI(panel.url, apiKey)
            let collected = try await loadInstances(using: api)
            instances = collected.sorted {
                $0.nickname.localizedCaseInsensitiveCompare($1.nickname) == .orderedAscending
            }
            hasLoaded = true
            publishStatuses()
            #if DEBUG
            writeDiagnose(error: nil)
            #endif
        } catch is CancellationError {
            // 取消（换面板 / 视图消失）不算错误。
        } catch {
            errorMessage = MCSManagerErrorText.describe(error)
            #if DEBUG
            writeDiagnose(error: errorMessage)
            #endif
        }
    }

    #if DEBUG
    /// **仅 DEBUG** 的验收钩子：`ORZMC_DEMO_MCSM_DIAGNOSE=1` 时把本次刷新的结果写到
    /// `Caches/orzmc-mcsm-<面板 id>.json`。
    ///
    /// 为什么需要它：真机/桌面上"有没有实例"只能靠截图看，而截图会受前台应用、滚动位置影响
    /// （iPhone SE 上 MCSM 分组在折叠线下）。有这个文件就能直接核对：
    /// 角色、实例数、每台实例的归一化状态、失败原因。
    func writeDiagnose(error: String?) {
        guard ProcessInfo.processInfo.environment["ORZMC_DEMO_MCSM_DIAGNOSE"] == "1" else { return }
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let snapshot: [String: Any] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "panel": panel?.label ?? "-",
            "url": panel?.url.absoluteString ?? "-",
            "hasLoaded": hasLoaded,
            "error": error ?? NSNull(),
            "instances": instances.map { instance in
                [
                    "id": instance.id,
                    "nickname": instance.nickname,
                    "state": instance.status.remoteState.rawValue,
                    "rawStatus": instance.status.rawValue,
                    "address": instance.address ?? NSNull(),
                ] as [String: Any]
            },
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: snapshot,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        let name = "orzmc-mcsm-\(panel?.id.uuidString ?? "nopanel").json"
        try? data.write(to: directory.appendingPathComponent(name))
    }
    #endif

    /// 按**账号权限**选入口：
    ///
    /// - 管理员（`permission >= 10`）：按节点列**全部**实例（管理员自己的 `instances` 通常是空的）；
    /// - 普通用户：`GET /api/auth?advanced=true` 列**自己的**实例 —— 管理员端点对他们一律 403
    ///   （面板文案还可能误导成「密钥不正确」）。
    private func loadInstances(using api: any MCSManagerPanelAPI) async throws -> [MCSManagerInstance] {
        let user = try await api.currentUser(advancedInstances: true)

        // 明确的普通用户：面板只允许列自己的实例，别去碰管理员端点（对普通 key 一律 403）。
        if let permission = user.permission, permission < MCSManagerRole.admin {
            return user.instances
        }

        do {
            return try await adminInstances(using: api)
        } catch let error as MCSManagerModelError {
            // 面板没给 permission（老版本）或值是管理员、但管理员端点仍 403：
            // 说明这个 key 其实是普通用户 —— 用它自己的实例，而不是把 403 丢给用户。
            if case .unauthorized = error, !user.instances.isEmpty {
                return user.instances
            }
            throw error
        }
    }

    /// 管理员视角：面板所有节点上的全部实例（每页 50，按 `maxPage` 取全）。
    private func adminInstances(using api: any MCSManagerPanelAPI) async throws -> [MCSManagerInstance] {
        var collected: [MCSManagerInstance] = []
        for daemon in try await api.daemons() {
            // 节点掉线时面板会直接报错，跳过它而不是让整个刷新失败。
            guard daemon.available else { continue }
            collected += try await instances(of: daemon.uuid, using: api)
        }
        return collected
    }

    /// 一个节点上的全部实例（面板每页最多 50，按 `maxPage` 取全）。
    private func instances(of daemonID: String, using api: any MCSManagerPanelAPI) async throws
        -> [MCSManagerInstance]
    {
        var result: [MCSManagerInstance] = []
        var page = 1
        while true {
            let body = try await api.instances(daemonID: daemonID, page: page, pageSize: 50)
            result += body.instances
            guard let maxPage = body.maxPage, page < maxPage else { break }
            page += 1
            if page > 20 { break }   // 防御：面板给出的 maxPage 异常时不要死循环
        }
        return result
    }

    /// 把快照里的状态喂给状态中心（**唯一写入口**，只在真变化时发事件）。
    func publishStatuses() {
        for instance in instances {
            statusCenter.publish(
                RemoteInstanceStatus(state: instance.status.remoteState, rawStatus: instance.status.rawValue),
                for: instanceID(instance.id),
                source: .polling
            )
        }
    }

    // MARK: - 后台轮询

    /// 心跳间隔：每 5 秒问一次策略"该拉吗"；真正发请求的节奏由
    /// `RemoteStatusRefreshPolicy.minimumInterval`（10 秒）决定。MCSM 没有 WS，
    /// 所以每一次都会落到"按最小间隔轮询"这一支 —— 不另写节律。
    static let heartbeat: Duration = .seconds(5)

    func startBackgroundRefresh() {
        guard backgroundRefreshTask == nil else { return }
        backgroundRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.heartbeat)
                guard let self, !Task.isCancelled else { return }
                if statusCenter.shouldRefresh(
                    hasCredentials: hasCredentials,
                    isAppActive: isSceneActive,
                    isLoading: isLoading
                ) {
                    await reload()
                }
            }
        }
    }

    func stopBackgroundRefresh() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
    }

    // MARK: - 供应商抽象层

    func instanceID(_ id: String) -> RemoteInstanceID {
        RemoteInstanceID(provider: .mcsmanager, rawValue: id)
    }

    /// 列表/卡片要的一切（供应商无关）。
    func instanceSummaries() -> [RemoteInstanceSummary] {
        instances.map { instance in
            RemoteInstanceSummary(
                provider: .mcsmanager,
                rawID: instance.id,
                name: instance.nickname,
                address: instance.address,
                state: instance.status.remoteState
            )
        }
    }

    /// 挂到供应商抽象层上的适配器。动作（start/stop/restart）属于 P2-7 第 5 步，
    /// 现在只提供**只读**能力：执行动作明确报"不支持"，而不是假装成功。
    var hostingProvider: any RemoteHostingProvider {
        MCSManagerHostingProvider(model: self)
    }

}

/// `MCSManagerModel` 的供应商适配器（只读）。
@MainActor
struct MCSManagerHostingProvider: RemoteHostingProvider {

    nonisolated var kind: ProviderKind { .mcsmanager }

    let model: MCSManagerModel

    func listInstances() async throws -> [RemoteInstanceSummary] {
        model.instanceSummaries()
    }

    /// 动作是 P2-7 第 5 步的内容：现在明确报"不支持"，不假装成功。
    func perform(_ action: RemoteServerAction, on instance: RemoteInstanceID) async throws {
        guard instance.provider == kind else {
            throw RemoteHostingError.wrongProvider(expected: kind, actual: instance.provider)
        }
        throw RemoteHostingError.actionNotSupported(action)
    }
}
