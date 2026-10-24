//
//  ExarotonStatusCenter.swift
//  OrzMC
//

import Foundation

/// 一次状态变化事件。
///
/// 业务侧（列表、详情、通知、未来的统计）**统一订阅这个**，不要各自决定"该看 WS 还是 HTTP"。
///
/// 注意是 internal：`ServerStatus` 来自 SDK，不是 `public`，所以事件类型也不对外公开。
/// 这个仓库里 App 与这些类型在同一个 module，够用。
struct RemoteStatusEvent: Equatable, Sendable {
    enum Source: String, Sendable {
        /// WebSocket 推送（详情页打开期间）。
        case webSocket
        /// HTTP 轮询兜底（任何页面都在跑）。
        case polling
        /// 本地先行值（例如调试钩子）。
        case local
    }

    let serverID: String
    /// 用 rawValue 而不是 `ServerStatus`：SDK 的枚举没标 `Sendable`，
    /// 事件要跨隔离域流动，所以存 Int，对外再算回枚举。
    let previousRaw: Int?
    let statusRaw: Int
    let source: Source
    let at: Date

    var status: ServerStatus { ServerStatus(rawValue: statusRaw) ?? .UNKNOWN }
    var previous: ServerStatus? { previousRaw.map { ServerStatus(rawValue: $0) ?? .UNKNOWN } }
    var isChange: Bool { previousRaw != nil && previousRaw != statusRaw }
}

/// 「现在该不该去拉一次 HTTP 状态」——纯决策，可单测。
///
/// 两条输入通道（WebSocket 推送 / HTTP 轮询）不是二选一，而是**同一件事的两个来源**：
/// WS 安静了（掉线、切后台、本来就没连）就必须靠轮询兜底；
/// 之前用 `isLive`（= `isConnected || readyServerID != nil`）判断，而 `readyServerID`
/// 在 WS 掉线后不会清空 → 轮询被永久跳过 → 状态卡死（真机反馈「一直停在加载中」）。
public enum RemoteStatusRefreshPolicy {

    /// WS 多久没消息就算"不活跃"，交给轮询兜底。
    public static let webSocketSilentAfter: TimeInterval = 30
    /// 两次轮询的最小间隔。
    public static let minimumInterval: TimeInterval = 10
    /// 一次刷新超过这个时间还没结束，视为卡住，允许再发（`reloadList` 自己有 `isLoadingList` 互斥）。
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

extension ExarotonServerModel {

    /// 订阅状态变化（每个订阅者一条独立流）。业务侧只需要 `for await event in model.statusEvents()`。
    func statusEvents() -> AsyncStream<RemoteStatusEvent> {
        AsyncStream { continuation in
            let id = UUID()
            statusSubscribers[id] = continuation
            continuation.onTermination = { @Sendable [weak self] _ in
                Task { @MainActor in self?.statusSubscribers[id] = nil }
            }
        }
    }

    /// **唯一**的状态入口：WS 推送、HTTP 轮询、调试注入都从这里进。
    ///
    /// - 只在状态**真的变化**时对外发事件（重复推送不打扰订阅者）；
    /// - 同时更新快照 `liveStatuses`（界面用 `effectiveStatus(for:)` 读）。
    func publishStatus(_ status: ServerStatus, for serverID: String, source: RemoteStatusEvent.Source) {
        let previous = liveStatuses[serverID]
        liveStatuses[serverID] = status
        lastStatusSource[serverID] = source
        lastStatusChangeAt[serverID] = Date()
        if previous != status { statusVersion &+= 1 }

        guard previous != status else { return }
        let event = RemoteStatusEvent(
            serverID: serverID,
            previousRaw: previous?.rawValue,
            statusRaw: status.rawValue,
            source: source,
            at: Date()
        )
        for continuation in statusSubscribers.values { continuation.yield(event) }
    }

    /// WS 收到任何消息都算"活着"（包括 keep-alive）。
    func noteWebSocketActivity() { lastWebSocketActivity = Date() }
}
