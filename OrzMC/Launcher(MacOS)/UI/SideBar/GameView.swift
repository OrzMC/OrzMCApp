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

        GameList(
            versions: catalog.filtered,
            selectedVersion: $catalog.selected,
            installStates: catalog.installStates,
            isOnlyRelease: catalog.releaseOnly,
            canUseShortcut: !app.launch.isLaunching
        )
        .sideBarTool(
            showOnlyRelease: $catalog.releaseOnly,
            isFetchingGameVersions: Binding(
                get: { catalog.isLoading },
                set: { _ in }
            )
        ) {
            Task { await app.loadVersions() }
        }
        // 侧边栏里的搜索：用 `.sidebar` 让系统把它放在列表上方（macOS 14 侧边栏样式），
        // 而不是挤进窗口工具栏、和右侧详情的按钮抢位置。
        .searchable(text: $catalog.searchText, placement: .sidebar, prompt: "Filter a version")
        .task {
            guard catalog.versions.isEmpty else { return }
            await app.loadVersions()
        }
        .toolbar {
            ToolbarItem {
                Button {
                    // 远程托管是独立的管理面，用独立窗口承载，不混进“本机实例”的导航栈。
                    openWindow(id: "remote")
                } label: {
                    Label("Remote Servers", systemImage: "server.rack")
                }
                .help("Manage exaroton remote servers in a separate window")
            }
        }
    }
}

/// 当前版本的启动配置（放在详情页 `Form` 的顶部）。
///
/// 返回 `Section`，由 `BasicInfo` 的 `Form` 直接使用；所有控件用系统组件：
/// `LabeledContent` / `Picker(.segmented/.menu)` / `TextField(.roundedBorder)` / `OrzMCBanner`。
struct LaunchControls: View {

    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            if let version = app.catalog.selected {
                content(for: version)
            }
        } header: {
            Label("Launch", systemImage: "play.circle")
        }
    }

    @ViewBuilder
    private func content(for version: Version) -> some View {
        // 一行：版本 + 模式。避免“Game Version / Mode”两整行占高度。
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            Text(version.id)
                .font(OrzMCTheme.Typography.numeric.weight(.semibold))
            OrzMCTag(version.localizedBuildTypeTitle)

            Spacer(minLength: OrzMCTheme.Spacing.sm)

            Picker("Mode", selection: modeBinding) {
                ForEach(GameMode.allCases) { mode in
                    Text(modeLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 170)
            .disabled(app.launch.isLaunching)
        }

        // 一行：Java 状态。比原来的三行（标题 / 已装 / 需要）省一半高度。
        if app.java.isVisible {
            javaStatusRow
        }

        // 一行：客户端用户名 / 服务端核心 + Start。
        if app.gameMode == .client {
            LabeledContent("Username") {
                HStack(spacing: OrzMCTheme.Spacing.sm) {
                    TextField("", text: usernameBinding, prompt: Text("Offline player name"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .onSubmit { app.start() }
                        .disabled(app.launch.isLaunching)
                    startButton
                }
            }
        } else {
            HStack(spacing: OrzMCTheme.Spacing.sm) {
                Text("Core")
                    .foregroundStyle(.secondary)
                Picker("Server Core", selection: serverSoftwareBinding) {
                    ForEach(SettingsModel.ServerSoftware.allCases) { software in
                        Text(software.rawValue).tag(software)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .disabled(app.launch.isLaunching)
                Spacer(minLength: 0)
                startButton
            }
        }

        if app.launch.progress.isRunning {
            HStack(spacing: OrzMCTheme.Spacing.xs) {
                ProgressView()
                    .controlSize(.small)
                Text(app.launch.progress.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else if app.launch.progress.isFinished {
            Label("Ready", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(OrzMCTheme.Palette.success)
        }

        if let message = app.settings.memoryValidationMessage {
            OrzMCBanner("Invalid memory setting: \(message)", role: .error)
        }
    }

    private var javaStatusRow: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            Label("Java", systemImage: "cup.and.saucer")
                .font(.callout)
            Text(javaSummary)
                .font(OrzMCTheme.Typography.numeric)
                .foregroundStyle(.secondary)

            Spacer(minLength: OrzMCTheme.Spacing.sm)

            OrzMCStatusBadge(verbatim: javaStatusText, style: javaStatusStyle)

            Button {
                app.java.refresh()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .buttonStyle(.borderless)
            .help("Rescan the managed Java runtimes under the game folder")
        }
    }

    private var javaSummary: String {
        let installed = app.java.installedMajors.isEmpty
            ? String(localized: "None")
            : app.java.installedMajors.map(String.init).joined(separator: ", ")
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

    private var startButton: some View {
        Button {
            app.start()
        } label: {
            Label("Start \(app.localizedGameModeTitle)", systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .fixedSize()
        .disabled(!app.canStart)
        .help(startHelp)
    }
}

#Preview {
    GameView()
        .frame(width: Constants.sidebarWidth, height: Constants.minHeight)
        .environment(AppModel())
}
