//
//  RemoteStatusCenter.swift
//  OrzMCRemoteHosting
//
//  P2-7 第 2 步：把 exaroton 专用的状态中心泛化成**供应商无关**的实现。
//
//  唯一规则（见 `docs/remote-status-source.md`）：
//    WebSocket 推送与 HTTP 轮询**不是二选一**，而是同一件事的两个来源；
//    两个来源都只能从 `publish(_:for:source:)` 这一个入口写进来，业务侧只订阅 `events()`。
//

import Foundation

/// 一次状态是从哪一路来的。
public enum RemoteStatusSource: String, CaseIterable, Codable, Sendable {
    /// WebSocket / SSE 等推送通道（实时，但只在连接期间有）。
    case webSocket
    /// HTTP 轮询（推送安静时的兜底）。
    case polling
    /// 本地先行值（调试注入、离线缓存）。
    case local
}

/// 一条实例状态，两个视图：
///
/// - `state`：**归一化**状态（徽章、动作可用性、跨供应商判断只认它）；
/// - `rawStatus`：供应商自己的状态码（exaroton 的 `ServerStatus.rawValue`）。界面需要
///   区分「启动中 / 加载中 / 准备中」这类细节时用它；MCSM 之类没有数字状态码的供应商给 `nil`。
public struct RemoteInstanceStatus: Equatable, Sendable {
    public let state: RemoteServerState
    public let rawStatus: Int?

    public init(state: RemoteServerState, rawStatus: Int? = nil) {
        self.state = state
        self.rawStatus = rawStatus
    }
}

/// 一次状态变化事件。
///
/// 只在状态**真的变化**时发出（重复推送不打扰订阅者）。
public struct RemoteStatusChange: Equatable, Sendable {
    public let instance: RemoteInstanceID
    public let previous: RemoteInstanceStatus?
    public let status: RemoteInstanceStatus
    public let source: RemoteStatusSource
    public let at: Date

    public init(
        instance: RemoteInstanceID,
        previous: RemoteInstanceStatus?,
        status: RemoteInstanceStatus,
        source: RemoteStatusSource,
        at: Date
    ) {
        self.instance = instance
        self.previous = previous
        self.status = status
        self.source = source
        self.at = at
    }

    /// 第一次观测到某个实例时为 `false`（没有"之前"）。
    public var isChange: Bool { previous != nil && previous != status }
}

/// 供应商无关的状态中心：**一个账号/面板一份**。
///
/// 为什么一个账号一份：WS 连接、轮询节律、"最近一次刷新"都是账号级的；
/// 多账号时每份中心各自跑，互不影响（"切换/删除账号不影响其他账号的轮询"）。
@MainActor
public final class RemoteStatusCenter {

    public init() {}

    // MARK: - 状态快照

    private var statuses: [RemoteInstanceID: RemoteInstanceStatus] = [:]
    private var sources: [RemoteInstanceID: RemoteStatusSource] = [:]
    private var subscribers: [UUID: AsyncStream<RemoteStatusChange>.Continuation] = [:]

    /// 状态**真的变化**的次数。界面用它做 `@Observable` 的版本号（`onChange(of:)`）。
    public private(set) var version: Int = 0

    public func status(for instance: RemoteInstanceID) -> RemoteInstanceStatus? {
        statuses[instance]
    }

    /// 当前所有已推送的状态（界面/调试用；不要拿它当"服务器列表"）。
    public var allStatuses: [RemoteInstanceID: RemoteInstanceStatus] {
        statuses
    }

    /// 最近一次状态来自哪一路（排查用）。
    public func lastSource(for instance: RemoteInstanceID) -> RemoteStatusSource? {
        sources[instance]
    }

    // MARK: - 唯一写入口

    /// 写入一条状态。**这是唯一入口**：WS 推送、HTTP 轮询、调试注入都走这里。
    ///
    /// - 只在状态真的变化时对外发事件并递增 `version`；
    /// - 返回是否算一次变化。
    @discardableResult
    public func publish(
        _ status: RemoteInstanceStatus,
        for instance: RemoteInstanceID,
        source: RemoteStatusSource,
        at date: Date = Date()
    ) -> Bool {
        let previous = statuses[instance]
        statuses[instance] = status
        sources[instance] = source

        guard previous != status else { return false }

        version &+= 1
        let change = RemoteStatusChange(
            instance: instance,
            previous: previous,
            status: status,
            source: source,
            at: date
        )
        for continuation in subscribers.values { continuation.yield(change) }
        return true
    }

    /// 订阅状态变化。每个订阅者一条独立流；`AsyncStream` 结束（任务取消/迭代器释放）自动退订。
    public func events() -> AsyncStream<RemoteStatusChange> {
        AsyncStream { continuation in
            let id = UUID()
            subscribers[id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in self?.subscribers[id] = nil }
            }
        }
    }

    /// 丢掉某个实例的快照（实例已不存在 / 换账号后清残留）。
    /// 不算"状态变化"：不发事件、不递增 `version`（实例消失不是它变了个状态）。
    public func forget(_ instance: RemoteInstanceID) {
        statuses[instance] = nil
        sources[instance] = nil
    }

    /// 清空（换账号 / 退出登录）。订阅者保留：界面不用重新订阅。
    public func reset() {
        statuses.removeAll()
        sources.removeAll()
        lastWebSocketActivityAt = nil
        lastRefreshStartedAt = nil
        lastRefreshFinishedAt = nil
    }

    // MARK: - 刷新节律（每个账号一套）

    /// 最近一次推送通道收到**任何**消息（含 keep-alive）的时间；`nil` = 从未连上。
    public private(set) var lastWebSocketActivityAt: Date?
    public private(set) var lastRefreshStartedAt: Date?
    public private(set) var lastRefreshFinishedAt: Date?

    /// 推送通道收到任何消息都算"它还活着"——轮询据此判断要不要兜底。
    public func noteWebSocketActivity(at date: Date = Date()) {
        lastWebSocketActivityAt = date
    }

    public func beginRefresh(at date: Date = Date()) {
        lastRefreshStartedAt = date
    }

    public func finishRefresh(at date: Date = Date()) {
        lastRefreshFinishedAt = date
    }

    /// 现在该不该去拉一次 HTTP 快照。判据全部在 `RemoteStatusRefreshPolicy`（纯函数，可单测）。
    ///
    /// - `isLoading` 由调用方给：它描述的是"一次刷新是否在途"，属于调用方的行为；
    /// - `hasCredentials == false`（还没填 token / 面板地址）时永远不轮询。
    public func shouldRefresh(
        hasCredentials: Bool,
        isAppActive: Bool,
        isLoading: Bool,
        now: Date = Date()
    ) -> Bool {
        RemoteStatusRefreshPolicy.shouldRefresh(
            hasToken: hasCredentials,
            isAppActive: isAppActive,
            lastWebSocketActivity: lastWebSocketActivityAt,
            lastRefreshFinished: lastRefreshFinishedAt,
            refreshStartedAt: isLoading ? lastRefreshStartedAt : nil,
            isLoading: isLoading,
            now: now
        )
    }
}

/// 「现在该不该去拉一次 HTTP 状态」——纯决策，可单测。
///
/// 两条输入通道（WebSocket 推送 / HTTP 轮询）不是二选一，而是**同一件事的两个来源**：
/// WS 安静了（掉线、切后台、本来就没连）就必须靠轮询兜底；
/// 之前用 `isLive`（= `isConnected || readyServerID != nil`）判断，而 `readyServerID`
/// 在 WS 掉线后不会清空 → 轮询被永久跳过 → 状态卡死（真机反馈「一直停在加载中」）。
///
/// ⚠️ **P2-7 红线**：`webSocketSilentAfter`（30 秒）这个判据不要改。
public enum RemoteStatusRefreshPolicy {

    /// WS 多久没消息就算"不活跃"，交给轮询兜底。
    public static let webSocketSilentAfter: TimeInterval = 30
    /// 两次轮询的最小间隔。
    public static let minimumInterval: TimeInterval = 10
    /// 一次刷新超过这个时间还没结束，视为卡住，允许再发（`reloadList` 自己有互斥）。
    public static let stuckAfter: TimeInterval = 25

    public static func shouldRefresh(
        hasToken: Bool,
        isAppActive: Bool,
        lastWebSocketActivity: Date?,
        lastRefreshFinished: Date?,
        refreshStartedAt: Date?,
        isLoading: Bool,
        now: Date
    ) -> Bool {
        guard hasToken, isAppActive else { return false }

        // 刷新在途：没卡住就等它，卡住了就允许重来。
        if isLoading {
            guard let started = refreshStartedAt else { return false }
            return now.timeIntervalSince(started) > stuckAfter
        }

        // WS 还活着（最近有消息）就不用拉 HTTP。
        if let activity = lastWebSocketActivity,
           now.timeIntervalSince(activity) < webSocketSilentAfter {
            return false
        }

        guard let finished = lastRefreshFinished else { return true }
        return now.timeIntervalSince(finished) >= minimumInterval
    }
}
