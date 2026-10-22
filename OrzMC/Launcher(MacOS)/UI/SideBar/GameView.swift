//
//  GameView.swift
//  OrzMC
//
//  Created by joker on 4/26/24.
//

import Game
import MojangAPI
import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 侧边栏：**只做导航**（版本列表 + 搜索 + 过滤 + 刷新）。
///
/// 启动配置（模式 / 类型 / 玩家名 / Java / 启动）不再挤在侧边栏底部，
/// 而是收进窗口标题栏（`LaunchToolbar`）。这样：
/// - 侧边栏的职责单一：选版本；
/// - 详情页成为“当前版本的实例页”：目录 + 控制台 + 插件 + 生命周期；
/// - 窗口变窄时列表不会被表单压缩。
struct GameView: View {

    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        @Bindable var catalog = app.catalog

        VStack(spacing: 0) {
            sidebarHeader
            GameList(
                versions: catalog.filtered,
                selectedVersion: $catalog.selected,
                installStates: catalog.installStates,
                latestReleaseId: catalog.latestReleaseId,
                latestSnapshotId: catalog.latestSnapshotId,
                isOnlyRelease: catalog.releaseOnly,
                canUseShortcut: !app.launch.isLaunching
            )
            // 键盘导航装在**列表**上：↑/↓ 走一格、⌘↑/⌘↓ 跳首末；
            // 正在编辑文本（搜索框等）时不拦截，方向键仍归输入框。
            .versionListKeyboardNavigation { delta, jumpToEdge in
                catalog.stepSelection(by: delta, jumpToEdge: jumpToEdge)
            }
        }
        .task {
            guard catalog.versions.isEmpty else { return }
            await app.loadVersions()
        }
        .toolbar {
            // 窗口级入口：外部链接 + 远程服务器，与系统的侧边栏开关同一排。
            ToolbarItem {
                LinkMenu()
            }

            ToolbarItem {
                Button {
                    // 远程托管是独立的管理面，用独立窗口承载，不混进"本机实例"的导航栈。
                    openWindow(id: "remote")
                } label: {
                    Label("Remote Servers", systemImage: "server.rack")
                }
                .help("Manage exaroton remote servers in a separate window")
            }
        }
    }

    /// 侧边栏顶部：搜索行 + 清单更新时间。
    ///
    /// 不画分隔线、不加不透明背景：让"搜索 → 更新时间 → 列表"读起来是**一整块**，
    /// 而不是被线切成三段。
    private var sidebarHeader: some View {
        @Bindable var catalog = app.catalog

        return VStack(alignment: .leading, spacing: 4) {
            SidebarSearchBar(
                searchText: $catalog.searchText,
                releaseOnly: $catalog.releaseOnly,
                isLoading: catalog.isLoading
            ) {
                Task { await app.loadVersions() }
            }

            HStack(spacing: 5) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.caption2)
                    .accessibilityHidden(true)
                Text(refreshSummary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 12)
            .padding(.bottom, 2)
        }
        .padding(.bottom, 4)
    }

    private var refreshSummary: String {
        guard let date = app.catalog.lastRefreshedAt else {
            return String(localized: "Version info not refreshed yet")
        }
        let day = GameList.dayText(VersionDateText.day(for: date))
        let time = VersionDateText.timeText(for: date)
        return String(localized: "Version info updated \(day) \(time)")
    }
}

#Preview {
    GameView()
        .frame(width: Constants.sidebarWidth, height: Constants.minHeight)
        .environment(AppModel())
}
