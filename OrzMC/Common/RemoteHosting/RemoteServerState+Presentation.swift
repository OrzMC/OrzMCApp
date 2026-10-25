//
//  RemoteServerState+Presentation.swift
//  OrzMC
//
//  供应商无关的状态 → 展示（文案 + 徽章风格）。
//
//  文案复用 exaroton 那套已经翻好的键（Online / Offline / Starting… ），所以不需要新翻译；
//  徽章只有一个实现（`OrzMCStatusBadge`），这里只决定用哪种语义色。
//

import OrzMCDesignSystem
import OrzMCRemoteHosting
import SwiftUI

extension RemoteServerState {

    var localizedTitle: String {
        switch self {
        case .online: return String(localized: "Online")
        case .offline: return String(localized: "Offline")
        case .starting: return String(localized: "Starting…")
        case .stopping: return String(localized: "Stopping…")
        case .restarting: return String(localized: "Restarting…")
        case .unknown: return String(localized: "Unknown status")
        }
    }

    var statusStyle: OrzMCStatusStyle {
        switch self {
        case .online: return .running
        case .offline: return .idle
        case .starting, .stopping, .restarting: return .busy
        // 未知 = 状态没稳定 → 过渡态（和 exaroton 的 .UNKNOWN 处理一致）
        case .unknown: return .busy
        }
    }

    /// 是否处于过渡态（此列动作一律不允许）。
    var isTransitional: Bool {
        switch self {
        case .online, .offline: return false
        case .starting, .stopping, .restarting, .unknown: return true
        }
    }
}
