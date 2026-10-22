import Foundation

/// 远程 WebSocket 连接的「代数」。
///
/// 为什么需要：`ExarotonWebSocketAPI` 用 `callbackQueue.async` 投递回调，
/// `disconnect()` + `reset()` 之后仍可能有**上一条连接的回调**排在主队列里。
/// 直接执行就会把已经清空的状态写回来（典型症状：离开详情后仍显示上一次的断线原因）。
///
/// 用法：建立/关闭连接时 `advance()`，把当时的代号交给该连接的 delegate；
/// 回调到达时用 `accepts(_:)` 校验，旧代号直接丢弃。
public struct ConnectionEpoch: Equatable, Sendable {
    public private(set) var current = 0

    public init() {}

    /// 建立或关闭连接时调用：让所有在途回调失效，并返回新代号。
    @discardableResult
    public mutating func advance() -> Int {
        current &+= 1
        return current
    }

    /// 这个代号是否仍是当前连接（旧代号 = 迟到回调）。
    public func accepts(_ epoch: Int) -> Bool {
        epoch == current
    }
}
