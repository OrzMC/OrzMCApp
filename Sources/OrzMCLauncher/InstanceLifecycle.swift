import Foundation

/// 服务端实例的生命周期操作（详情页实例栏的四个按钮）。
///
/// 语义（与常见面板一致，别混用）：
/// - `start`：启动（无确认）；
/// - `restart`：**先停止再启动**（会断开在线玩家 → 二次确认）；
/// - `stop`：**优雅停止** —— 往控制台送 `stop`，让服务端自己存档退出（会断开玩家 → 确认）；
/// - `terminate`：**终止进程** —— 不等它自己退出（`SIGTERM` → 超时 `SIGKILL`），
///   世界可能来不及完整保存（→ 确认，且要提示这一点）。
public enum ServerLifecycleAction: String, CaseIterable, Sendable {
    case start
    case restart
    case stop
    case terminate

    public var title: String {
        switch self {
        case .start: return "start"
        case .restart: return "restart"
        case .stop: return "stop"
        case .terminate: return "terminate"
        }
    }

    /// 需要二次确认（打断玩家 / 可能丢存档）。
    public var requiresConfirmation: Bool {
        switch self {
        case .start: return false
        case .restart, .stop, .terminate: return true
        }
    }

    /// 只有运行中才可用。
    public var requiresRunning: Bool {
        switch self {
        case .start: return false
        case .restart, .stop, .terminate: return true
        }
    }
}

/// 某实例当前正在做的事（驱动"按钮禁用 + 转圈 + 防连点"）。
public enum InstanceActivity: Sendable, Equatable {
    case idle
    case starting
    /// 优雅停止（送 `stop`）。
    case stopping
    /// 强制终止（`SIGTERM`/`SIGKILL`）。
    case terminating
    case restarting

    public var isBusy: Bool { self != .idle }

    /// 状态徽标文案（`nil` = 不显示）。
    public var statusOverride: String? {
        switch self {
        case .idle: return nil
        case .starting: return "Starting…"
        case .stopping: return "Stopping…"
        case .terminating: return "Terminating…"
        case .restarting: return "Restarting…"
        }
    }
}

/// 实例栏里四个按钮 + 控制台/删除的可用性（纯逻辑，单测覆盖）。
public struct InstanceActionAvailability: Sendable, Equatable {
    public var canStart: Bool
    public var canRestart: Bool
    public var canStop: Bool
    public var canTerminate: Bool
    public var canConsole: Bool
    public var canDelete: Bool

    /// - Parameters:
    ///   - isRunning: 实例进程是否活着（登记表 + 探活）。
    ///   - activity: 当前进行中的操作（`idle` = 没在忙）。
    ///   - canControlGracefully: 是否**持有进程句柄**（能往 stdin 送 `stop`）。
    ///     App 重启后接着管上一个自己以前启动的服务端时，句柄已经没了 —— 只能终止，不能优雅停止。
    public static func make(
        isRunning: Bool,
        activity: InstanceActivity,
        canControlGracefully: Bool
    ) -> InstanceActionAvailability {
        let busy = activity.isBusy
        return InstanceActionAvailability(
            canStart: !busy && !isRunning,
            canRestart: !busy && isRunning,
            canStop: !busy && isRunning && canControlGracefully,
            canTerminate: !busy && isRunning,
            canConsole: !busy,
            canDelete: !busy && !isRunning
        )
    }

    public func isEnabled(_ action: ServerLifecycleAction) -> Bool {
        switch action {
        case .start: return canStart
        case .restart: return canRestart
        case .stop: return canStop
        case .terminate: return canTerminate
        }
    }
}
