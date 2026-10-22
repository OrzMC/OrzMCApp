import Foundation

/// 远程实例的**在途操作互斥**（纯逻辑，可单测）。
///
/// 规则（2026-10-22 交互审查 §2：请求期间必须有模型级防重入，不能只靠按钮 disabled）：
/// - 同一实例同一时刻只允许**一个**在途请求：生命周期动作（start / stop / restart）与内存变更互相排除；
/// - 占用必须在**首次 await 之前**完成，否则网络慢时两次点击都会进到请求里；
/// - 不同实例互不影响（可以同时操作两台服务器）。
///
/// 视图只读取 `pendingActions` / `pendingMemoryChanges` 决定禁用与忙碌态。
public struct RemoteActionGate: Equatable, Sendable {
    /// 正在提交生命周期动作的实例。
    public private(set) var pendingActions: Set<String> = []
    /// 正在提交内存变更的实例。
    public private(set) var pendingMemoryChanges: Set<String> = []

    public init() {}

    /// 是否有任何实例在途（列表页据此禁用「账号」等全局动作）。
    public var isBusy: Bool { !pendingActions.isEmpty || !pendingMemoryChanges.isEmpty }

    public func isBusy(serverID: String) -> Bool {
        pendingActions.contains(serverID) || pendingMemoryChanges.contains(serverID)
    }

    /// 占用实例以提交生命周期动作；已被占用时返回 `false`，调用方应直接放弃这次点击。
    public mutating func beginAction(serverID: String) -> Bool {
        guard !isBusy(serverID: serverID) else { return false }
        pendingActions.insert(serverID)
        return true
    }

    public mutating func endAction(serverID: String) {
        pendingActions.remove(serverID)
    }

    /// 占用实例以提交内存变更；已被占用（含生命周期动作在途）时返回 `false`。
    public mutating func beginMemoryChange(serverID: String) -> Bool {
        guard !isBusy(serverID: serverID) else { return false }
        pendingMemoryChanges.insert(serverID)
        return true
    }

    public mutating func endMemoryChange(serverID: String) {
        pendingMemoryChanges.remove(serverID)
    }

    /// 换账号/清空远程状态时复位。
    public mutating func reset() {
        pendingActions.removeAll()
        pendingMemoryChanges.removeAll()
    }
}
