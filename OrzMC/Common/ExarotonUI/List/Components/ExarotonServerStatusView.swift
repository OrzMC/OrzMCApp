//
//  ExarotonServerStatusView.swift
//  OrzMC
//
//  Created by joker on 5/17/24.
//

import OrzMCDesignSystem
import SwiftUI

struct DisplayConfig {
    let imageName: String
    let foregroundColor: Color
    let animate: Bool

    init(
        _ imageName: String,
        _ foregroundColor: Color,
        _ animate: Bool = false
    ) {
        self.imageName = imageName
        self.foregroundColor = foregroundColor
        self.animate = animate
    }
}

extension ServerStatus {
    /// 过渡态（启动/停止/重启/保存/加载中）：此时**任何动作都会被服务端拒绝**，
    /// 界面据此禁用按钮并显示转圈。
    var isTransitional: Bool {
        switch self {
        case .STARTING, .STOPPING, .RESTARTING, .SAVING, .LOADING, .PENDING, .PREPARING:
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
        }
    }

    var statusStyle: OrzMCStatusStyle {
        switch self {
        case .OFFLINE: return .idle
        case .ONLINE: return .running
        case .STARTING, .STOPPING, .RESTARTING, .SAVING, .LOADING, .PENDING, .PREPARING: return .busy
        case .CRASHED: return .error
        }
    }

    /// 状态 → 图标/颜色/是否脉冲。
    ///
    /// 语义约定：离线是**中性**（不是错误），崩溃才是红色；进行态用橙色 + 脉冲。
    var displayConfig: DisplayConfig {
        switch self {
        case .OFFLINE:
            return .init("stop.circle", OrzMCTheme.Palette.idle)
        case .ONLINE:
            return .init("play.circle.fill", OrzMCTheme.Palette.success)
        case .STARTING, .LOADING, .PREPARING, .PENDING, .RESTARTING:
            return .init("arrow.triangle.2.circlepath", OrzMCTheme.Palette.warning, true)
        case .STOPPING, .SAVING:
            return .init("stop.circle", OrzMCTheme.Palette.warning, true)
        case .CRASHED:
            return .init("exclamationmark.triangle.fill", OrzMCTheme.Palette.danger)
        }
    }
}

struct ExarotonServerStatusView: View {
    let status: ServerStatus

    var body: some View {
        let config = status.displayConfig
        Image(systemName: config.imageName)
            .font(.title3)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(config.foregroundColor)
            // 系统符号动画（macOS 14 / iOS 17+），替代手写的 opacity + repeatForever：
            // 会尊重「减弱动态效果」，也不会出现“动画结束后图标停在 0 透明度”的坑。
            .symbolEffect(.pulse, options: .repeating, isActive: config.animate)
            .accessibilityLabel(Text(status.localizedTitle))
    }
}

#Preview {
    VStack(spacing: 10) {
        ForEach(ServerStatus.allCases, id: \.self) { status in
            HStack {
                Text(String(describing: status))
                Spacer()
                ExarotonServerStatusView(status: status)
                    .frame(width: 24, height: 24)
            }
        }
    }
    .padding()
}
