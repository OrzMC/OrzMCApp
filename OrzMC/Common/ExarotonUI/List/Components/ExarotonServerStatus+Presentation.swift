//
//  ExarotonServerStatus+Presentation.swift
//  OrzMC
//
//  服务端状态 → 展示语义（过渡态判定 / 文案 / 徽章风格）。
//
//  曾经这里还有一个自己画的 `ExarotonServerStatusView`（带 symbolEffect 脉冲），
//  和设计系统的 `OrzMCStatusBadge` 重复，且它的动画同样会在视图重建后停住 —— 已删除，
//  统一走 `OrzMCStatusBadge`（见 Sources/OrzMCDesignSystem/StatusBadge.swift）。
//

import OrzMCDesignSystem
import SwiftUI

extension ServerStatus {
    /// 过渡态（启动/停止/重启/保存/加载中）：此时**任何动作都会被服务端拒绝**，
    /// 界面据此禁用按钮并显示转圈。
    var isTransitional: Bool {
        switch self {
        case .STARTING, .STOPPING, .RESTARTING, .SAVING, .LOADING, .PENDING, .PREPARING, .TRANSFERRING:
            return true
        // 未知状态（SDK 遇到没见过的状态码）也按过渡态处理：状态没稳定前不许动作。
        case .UNKNOWN:
            return true
        case .ONLINE, .OFFLINE, .CRASHED:
            return false
        }
    }

    /// 状态展示名（本地化）。
    var localizedTitle: String {
        switch self {
        case .OFFLINE: return String(localized: "Offline")
        case .ONLINE: return String(localized: "Online")
        case .STARTING: return String(localized: "Starting…")
        case .STOPPING: return String(localized: "Stopping…")
        case .RESTARTING: return String(localized: "Restarting…")
        case .SAVING: return String(localized: "Saving…")
        case .LOADING: return String(localized: "Loading…")
        case .CRASHED: return String(localized: "Crashed")
        case .PENDING: return String(localized: "Pending…")
        case .PREPARING: return String(localized: "Preparing…")
        case .TRANSFERRING: return String(localized: "Transferring…")
        case .UNKNOWN: return String(localized: "Unknown status")
        }
    }

    var statusStyle: OrzMCStatusStyle {
        switch self {
        case .OFFLINE: return .idle
        case .ONLINE: return .running
        case .STARTING, .STOPPING, .RESTARTING, .SAVING, .LOADING, .PENDING, .PREPARING, .TRANSFERRING: return .busy
        case .UNKNOWN: return .busy
        case .CRASHED: return .error
        }
    }

}
