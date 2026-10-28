//
//  RemoteStopProgress.swift
//  OrzMCRemoteHosting
//
//  「优雅停止到底等了多久」——纯逻辑，可单测，不碰 UI 也不碰网络（P2-7 第 6 步 / B2）。
//
//  背景：MCSM 的停止是**异步**的。`/api/protected_instance/stop` 立刻返回 200，之后服务器自己
//  读档、保存、退出；面板的状态要先经过 `STOPPING` 才变 `STOPPED`。正常情况下几秒就完了，
//  但存档很大 / 插件卡死 / JVM 无响应时可能一直停在 `STOPPING` —— 那时唯一的出路是强杀。
//
//  所以界面要能回答两个问题：
//    1. 已经等了多久（让用户知道不是没反应）；
//    2. 该不该建议强杀（避免用户过早强杀丢掉存档，也避免他一直干等）。
//

import Foundation

/// 一次「停止」请求从提交到现在的时间与判定。
public struct RemoteStopProgress: Equatable, Sendable {
    /// 判定档位。阈值来自实测与面板自身行为：
    /// - 面板 `stop` 是异步的，正常 MC 服务器读完档退出通常 < 20 秒；
    /// - 面板对强杀的 HTTP 超时是 30 秒（`INSTANCE_KILL_TIMEOUT`）；
    /// - 超过 60 秒基本就是卡住了（插件死锁 / JVM 假死 / 存档损坏）。
    public enum Level: Equatable, Sendable {
        /// < 30 秒：正常等待，只需要告诉用户"在停"。
        case normal
        /// 30–60 秒：偏慢（存档大 / TPS 低），**可以**强杀，但不急。
        case slow
        /// ≥ 60 秒：多半是卡住了，界面上建议强杀。
        case stalled
    }

    /// 已等待秒数（负数按 0 处理：设备时钟回拨 / 未来时间不该显示"−3 秒"）。
    public let elapsed: TimeInterval

    public init(elapsed: TimeInterval) {
        self.elapsed = max(0, elapsed)
    }

    public init(since start: Date, now: Date = Date()) {
        self.init(elapsed: now.timeIntervalSince(start))
    }

    /// 展示用的整秒数。
    public var seconds: Int { Int(elapsed) }

    public var level: Level {
        if elapsed >= 60 { return .stalled }
        if elapsed >= 30 { return .slow }
        return .normal
    }

    /// 是否该在界面上提示"可以强制停止"（`slow` / `stalled`）。
    public var suggestsForceStop: Bool { level != .normal }
}
