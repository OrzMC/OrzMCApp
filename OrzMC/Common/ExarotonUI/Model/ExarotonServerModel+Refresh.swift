//
//  ExarotonServerModel+Refresh.swift
//  OrzMC
//

import Foundation

extension ExarotonServerModel {

    /// 轮询**心跳**间隔：每 5 秒问一次策略"现在该拉吗"。
    /// 真正发 HTTP 的节奏由 `RemoteStatusRefreshPolicy.minimumInterval`（10 秒）与
    /// "WS 是否安静"（30 秒）决定 —— 心跳比刷新快，才能在 WS 掉线后迅速接管。
    static let backgroundRefreshInterval: Duration = .seconds(5)

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
                    isAppActive: isSceneActive,
                    lastWebSocketActivity: lastWebSocketActivity,
                    lastRefreshFinished: lastRefreshFinished,
                    refreshStartedAt: refreshStartedAt,
                    isLoading: isLoadingList,
                    now: Date()
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
