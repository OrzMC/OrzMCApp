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
/// 启动配置（模式 / 用户名 / 服务端核心 / 内存 / Start）不再挤在侧边栏底部，
/// 而是放到详情页顶部的 [LaunchControls] 里。这样：
/// - 侧边栏的职责单一：选版本；
/// - 详情页成为“当前版本的控制台”：启动配置 + 实例目录 + 生命周期；
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

/// 当前版本的启动面板（详情页 `Form` 的第一段）。
///
/// 设计（2026-10-22 第七轮）：
/// - **主按钮放在卡片标题栏右侧**：不打游戏版本、不用滚到底，一眼能看到"要启动什么"；
/// - 用 `Grid` 固定 96pt 标签列 + 控件列，不再依赖 `LabeledContent`（那是"总是对不齐"的根源：
///   分段控件/菜单/输入框各自带不同的内边距）；
/// - 行顺序即操作顺序：类型（客户端/服务端 + 二级类型）→ 玩家名 → Java；
/// - 服务端模式下"玩家名"行不消失，而是显示一句说明，面板高度稳定、不会跳。
struct LaunchControls: View {
    @Environment(AppModel.self) private var app

    private let labelWidth: CGFloat = 96

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Divider()

            if app.catalog.selected != nil {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    typeRow
                    identityRow
                    javaRow
                }
            }

            if app.launch.progress.isRunning {
                HStack(spacing: OrzMCTheme.Spacing.xs) {
                    ProgressView().controlSize(.small)
                    Text(app.launch.progress.summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }

            if let message = app.settings.memoryValidationMessage {
                OrzMCBanner("Invalid memory setting: \(message)", role: .error)
            }
        }
        .padding(16)
        // macOS 26 起是液态玻璃，老系统是等效的填充 + 细描边（见 `OrzMCPanel`）。
        .orzMCPanel()
        .focusSection()
    }

    /// 卡片标题栏 = 标题 + 主按钮（始终在同一个位置）。
    private var header: some View {
        HStack(alignment: .center, spacing: OrzMCTheme.Spacing.sm) {
            Label("Launch", systemImage: "play.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if app.launch.progress.isFinished {
                Label("Ready", systemImage: "checkmark.seal.fill")
                    .font(.caption)
                    .foregroundStyle(OrzMCTheme.Palette.success)
            }

            Spacer(minLength: 0)

            Button {
                app.start()
            } label: {
                Label("Start \(app.localizedGameModeTitle)", systemImage: "play.fill")
                    .frame(minWidth: 120)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!app.canStart)
            .help(startHelp)
        }
        .padding(.bottom, 2)
    }

    // MARK: - 行

    /// 类型：客户端/服务端 + 该端的二级类型（客户端 Vanilla/Fabric；服务端核心）。
    private var typeRow: some View {
        GridRow {
            label("Mode")
            HStack(spacing: OrzMCTheme.Spacing.sm) {
                Picker("Mode", selection: modeBinding) {
                    ForEach(GameMode.allCases) { mode in
                        Text(modeLabel(mode)).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .frame(minWidth: 148)
                .disabled(app.launch.isLaunching)

                if app.gameMode == .client {
                    Picker("Client type", selection: clientTypeBinding) {
                        ForEach(SettingsModel.ClientKind.allCases) { kind in
                            Text(kind.rawValue).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(minWidth: 138)
                    .disabled(app.launch.isLaunching)
                } else {
                    // 和服务端核心用同一种分段控件：一行里都是"选项片"，不再混菜单（菜单的内边距是另一种对齐）。
                    Picker("Server Core", selection: serverSoftwareBinding) {
                        ForEach(SettingsModel.ServerSoftware.allCases) { software in
                            Text(software.rawValue).tag(software)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .fixedSize()
                    .disabled(app.launch.isLaunching)
                }

                Spacer(minLength: 0)
            }
        }
    }

    /// 归属：客户端填玩家名；服务端用一句说明占位（行不消失，面板不跳）。
    private var identityRow: some View {
        GridRow {
            label(app.gameMode == .client ? "Username" : "Account")
            if app.gameMode == .client {
                TextField("", text: usernameBinding, prompt: Text("Offline player name"))
                    .textFieldStyle(.roundedBorder)
                    .labelsHidden()
                    .multilineTextAlignment(.leading)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .onSubmit { app.start() }
                    .frame(maxWidth: 360, alignment: .leading)
                    .disabled(app.launch.isLaunching)
            } else {
                Text("Servers don't need a player name.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Java：已装版本 → 需要的版本 + 状态徽标 + 重新扫描。
    private var javaRow: some View {
        GridRow {
            label("Java")
            HStack(spacing: OrzMCTheme.Spacing.sm) {
                Text(javaSummary)
                    .font(OrzMCTheme.Typography.numeric)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                OrzMCStatusBadge(verbatim: javaStatusText, style: javaStatusStyle)

                Button("Rescan Java", systemImage: "arrow.triangle.2.circlepath") {
                    app.java.refresh()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Rescan the managed Java runtimes under the game folder")

                Spacer(minLength: 0)
            }
        }
    }

    private func label(_ key: LocalizedStringKey) -> some View {
        Text(key)
            .frame(width: labelWidth, alignment: .leading)
            .foregroundStyle(.secondary)
    }

    private var javaSummary: String {
        let installed = app.java.installedMajors.isEmpty
            ? String(localized: "None")
            : app.java.installedMajors.map(String.init).formatted(.list(type: .and))
        guard let required = app.java.requiredMajor else { return installed }
        return "\(installed) → \(required)"
    }

    private var javaStatusText: String {
        switch app.java.status {
        case .valid: return String(localized: "Ready")
        case .missing: return String(localized: "Will be installed")
        case .unknown: return String(localized: "Unknown")
        }
    }

    private var javaStatusStyle: OrzMCStatusStyle {
        switch app.java.status {
        case .valid: return .running
        case .missing: return .warning
        case .unknown: return .idle
        }
    }

    private func modeLabel(_ mode: GameMode) -> LocalizedStringKey {
        mode == .client ? "Client" : "Server"
    }

    private var modeBinding: Binding<GameMode> {
        Binding(
            get: { app.gameMode },
            set: { app.gameMode = $0 }
        )
    }

    private var usernameBinding: Binding<String> {
        Binding(
            get: { app.username },
            set: { app.username = $0 }
        )
    }

    private var clientTypeBinding: Binding<SettingsModel.ClientKind> {
        Binding(
            get: { app.settings.clientType },
            set: { app.settings.clientType = $0 }
        )
    }

    private var serverSoftwareBinding: Binding<SettingsModel.ServerSoftware> {
        Binding(
            get: { app.settings.serverSoftware },
            set: { app.settings.serverSoftware = $0 }
        )
    }

    private var startHelp: String {
        if app.isCurrentInstanceRunning {
            return String(localized: "\(app.localizedGameModeTitle) is already running")
        }
        return app.canStart
            ? String(localized: "Start \(app.localizedGameModeTitle)")
            : String(localized: "Select a version, enter a user name, and check the memory settings")
    }

}

#Preview {
    GameView()
        .frame(width: Constants.sidebarWidth, height: Constants.minHeight)
        .environment(AppModel())
}
