//
//  ExarotonServerModel+Refresh.swift
//  OrzMC
//

import Foundation

/// 「什么时候该去拉一次 HTTP 状态」的纯决策（可单测）。
///
/// WebSocket 是**按服务器**连的，而且只有详情页开着才连；一旦用户切到别的页面
/// （自建服务器、额度池、设置…），WS 就断了，状态只能靠轮询兜底。
/// 之前轮询挂在**列表视图**的 `.task` 上，切走页面就没了 → 服务器明明已自动关机，
/// 界面还显示「在线」（真机反馈）。
public enum RemoteStatusRefreshPolicy {
    public static func shouldRefresh(
        hasToken: Bool,
        isWebSocketLive: Bool,
        isAppActive: Bool,
        isLoading: Bool
    ) -> Bool {
        // 有 WS 就不必拉 HTTP（WS 会推状态）；没有 Token 也无从拉起。
        hasToken && !isWebSocketLive && isAppActive && !isLoading
    }
}

extension ExarotonServerModel {

    /// 默认轮询间隔。exaroton 的状态变化很"慢"（启动/停止以秒~分钟计），15 秒足够且不打扰服务端。
    static let backgroundRefreshInterval: Duration = .seconds(15)

    /// 启动后台状态轮询。**与视图生命周期解耦**（模型自带 Task），
    /// 所以切换页面不会中断；重复调用不会叠加多个循环。
    func startBackgroundRefresh() {
        guard backgroundRefreshTask == nil else { return }
        backgroundRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.backgroundRefreshInterval)
                guard let self, !Task.isCancelled else { return }
                if RemoteStatusRefreshPolicy.shouldRefresh(
                    hasToken: !token.isEmpty,
                    isWebSocketLive: isLive,
                    isAppActive: isSceneActive,
                    isLoading: isLoadingList
                ) {
                    await reloadList()
                }
            }
        }
    }

    func stopBackgroundRefresh() {
        backgroundRefreshTask?.cancel()
        backgroundRefreshTask = nil
    }
}
