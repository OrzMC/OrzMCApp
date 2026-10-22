import Foundation

/// 「该不该订阅远程流」的纯决策：只有**已连接 + 服务端在线**时才需要日志/指标流。
///
/// 其它情况（离线、崩溃、正在关闭、连接断开）都应把流停掉，避免对着一个不存在的
/// 服务端持续发 `stream stop`（旧实现靠 3s 定时器反复重发）。
public enum RemoteStreamingPolicy {
    public static func shouldStream(isConnected: Bool, isServerOnline: Bool) -> Bool {
        isConnected && isServerOnline
    }
}

/// 这一轮要开/关哪些流：`active` 是当前已订阅集合，`all` 是需要订阅的全部流。
///
/// 与具体框架无关（泛型 `Stream`），因此可以在不启动 WebSocket 的情况下单测；
/// 不要求 `Sendable`：只在主线程上算一次就用掉，第三方流类型也没有该约束。
public struct RemoteStreamPlan<Stream: Hashable>: Equatable {
    public let start: [Stream]
    public let stop: [Stream]

    public init(start: [Stream] = [], stop: [Stream] = []) {
        self.start = start
        self.stop = stop
    }

    public var isEmpty: Bool { start.isEmpty && stop.isEmpty }

    /// 期望订阅时补齐缺的流；期望停止时只停已订阅的流（不重复发指令）。
    public static func make(active: Set<Stream>, all: [Stream], isEnabled: Bool) -> RemoteStreamPlan<Stream> {
        isEnabled
            ? RemoteStreamPlan(start: all.filter { !active.contains($0) })
            : RemoteStreamPlan(stop: all.filter { active.contains($0) })
    }
}
