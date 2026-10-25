//
//  RemoteServerState.swift
//  OrzMCRemoteHosting
//
//  与供应商无关的实例状态 / 动作 / 列表策略（P2-7 抽象层）。
//

/// 一台远程实例（服务器）的**归一化**状态。
///
/// 各供应商给出的状态码不一样（exaroton 的 `ServerStatus`、MCSM 的守护进程状态），
/// 适配器负责把它们收敛到这几个值；界面只认这个枚举。
public enum RemoteServerState: String, Equatable, Sendable {
    case online
    case offline
    case starting
    case stopping
    case restarting
    case unknown
}

/// 与供应商无关的生命周期动作。
public enum RemoteServerAction: Equatable, Sendable {
    case start
    case stop
    case restart
}

/// 列表侧的纯逻辑（搜索、动作可用性）：可单测，不碰网络也不碰 UI。
public struct RemoteServerListPolicy: Sendable {
    public init() {}

    /// 搜索：按名称或地址匹配。**不按供应商过滤**——多供应商界面是分组展示，不是筛选。
    public func visibleInstances(
        from instances: [RemoteInstanceSummary],
        searchText: String
    ) -> [RemoteInstanceSummary] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return instances
        }
        return instances.filter { instance in
            instance.name.localizedCaseInsensitiveContains(query)
                || instance.address?.localizedCaseInsensitiveContains(query) == true
        }
    }

    /// 该状态下是否允许执行该动作。
    public func canPerform(_ action: RemoteServerAction, on state: RemoteServerState) -> Bool {
        switch (action, state) {
        // **过渡态（starting / stopping / restarting / loading…）一律不允许动作**：
        // exaroton 会直接拒绝，用户看到的就是"点了报错"（真机实测：启动中/停止中/重启中都会报）。
        case (.start, .offline), (.stop, .online), (.restart, .online):
            return true
        default:
            return false
        }
    }
}
