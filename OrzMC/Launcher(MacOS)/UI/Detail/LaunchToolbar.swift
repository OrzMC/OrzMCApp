//
//  LaunchToolbar.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 窗口标题栏里的「启动区」：**当前版本的启动参数**都收在顶部一排。
///
/// 设计（2026-10-22 第十一轮，维护者意见：详情页正文只放"各类客户端/服务端相关的内容"）：
/// - 左（紧跟标题，`.navigation`）：模式（客户端/服务器）+ 该端的二级类型（Vanilla/Fabric 或服务端核心）；
///   都是分段控件，点一下即切换，正文的实例区跟着换；
/// - 右（`.primaryAction`）：启动设置（玩家名 / Java，低频，收进 popover）+ 启动主按钮。
/// - 正文不再有"启动面板"，只留实例目录 / 控制台 / 插件这些**与当前版本实例相关**的内容。
///
/// 为什么玩家名不直接放工具栏：窄窗口（960pt）下"标题 + 两个分段 + 输入框 + 主按钮"会触发工具栏
/// 自动收纳（多出 `»` 溢出菜单），反而更难用；放进 popover 后宽度可控，
/// 且缺玩家名时按钮带感叹号徽标提示。
struct LaunchToolbar: ToolbarContent {

    @Environment(AppModel.self) private var app

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Mode", selection: modeBinding) {
                ForEach(GameMode.allCases) { mode in
                    Text(modeLabel(mode)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .disabled(app.launch.isLaunching)
            .help("Client or server instance")

            // 二级类型：客户端只有 2 个选项 → 分段；服务端核心有 3–4 个 → 下拉菜单。
            // 都塞成分段在 960pt 窗口里会把「启动」挤进工具栏的 `»` 溢出菜单（实测）。
            if app.gameMode == .client {
                Picker("Client type", selection: clientTypeBinding) {
                    ForEach(SettingsModel.ClientKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .disabled(app.launch.isLaunching)
                .help("Vanilla or Fabric client")
            } else {
                Picker("Server Core", selection: serverSoftwareBinding) {
                    ForEach(SettingsModel.ServerSoftware.allCases) { software in
                        Text(software.rawValue).tag(software)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .controlSize(.small)
                .fixedSize()
                .disabled(app.launch.isLaunching)
                .help("Which server core this instance runs")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            LaunchSettingsButton()
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                app.start()
            } label: {
                Label("Start \(app.localizedGameModeTitle)", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
                    .frame(minWidth: 84)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!app.canStart)
            .help(startHelp)
        }

        if app.launch.progress.isRunning {
            ToolbarItem(placement: .primaryAction) {
                ProgressView()
                    .controlSize(.small)
                    .help(app.launch.progress.summary)
                    .accessibilityLabel(Text(app.launch.progress.summary))
            }
        }
    }

    // MARK: - 绑定

    private var modeBinding: Binding<GameMode> {
        Binding(get: { app.gameMode }, set: { app.gameMode = $0 })
    }

    private var clientTypeBinding: Binding<SettingsModel.ClientKind> {
        Binding(get: { app.settings.clientType }, set: { app.settings.clientType = $0 })
    }

    private var serverSoftwareBinding: Binding<SettingsModel.ServerSoftware> {
        Binding(get: { app.settings.serverSoftware }, set: { app.settings.serverSoftware = $0 })
    }

    private func modeLabel(_ mode: GameMode) -> LocalizedStringKey {
        mode == .client ? "Client" : "Server"
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

/// 工具栏右侧的「启动设置」按钮：玩家名 + Java。
///
/// 低频项收进 popover，主界面只留一个图标；缺玩家名 / Java 未就绪时按钮带感叹号徽标，
/// 用户不会因为"启动按钮是灰的"而找不到原因。
struct LaunchSettingsButton: View {

    @Environment(AppModel.self) private var app
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Launch Settings", systemImage: needsAttention
                ? "person.crop.circle.badge.exclamationmark"
                : "person.crop.circle")
                .labelStyle(.iconOnly)
        }
        .help(helpText)
        .accessibilityLabel(Text("Launch Settings"))
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            LaunchSettingsPopover(isPresented: $isPresented)
                .environment(app)
        }
    }

    private var needsAttention: Bool {
        app.gameMode == .client && app.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var helpText: String {
        needsAttention
            ? String(localized: "Player name and Java runtime — the player name is still empty")
            : String(localized: "Player name and Java runtime")
    }
}

/// 「启动设置」popover 的内容：玩家名 / Java 状态 / 更多设置入口。
struct LaunchSettingsPopover: View {

    @Binding var isPresented: Bool

    @Environment(AppModel.self) private var app
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Launch Settings")
                .font(.headline)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Text("Username")
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    TextField("", text: usernameBinding, prompt: Text("Offline player name"))
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .frame(width: 180)
                        .disabled(app.gameMode == .server || app.launch.isLaunching)
                        .onSubmit { app.start() }
                }

                GridRow {
                    Text("Java")
                        .foregroundStyle(.secondary)
                        .frame(width: 64, alignment: .leading)
                    HStack(spacing: 8) {
                        Text(javaSummary)
                            .font(OrzMCTheme.Typography.numeric)
                            .lineLimit(1)
                        OrzMCStatusBadge(verbatim: javaStatusText, style: javaStatusStyle)
                        Button("Rescan Java", systemImage: "arrow.triangle.2.circlepath") {
                            app.java.refresh()
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Rescan the managed Java runtimes under the game folder")
                    }
                }
            }

            if app.gameMode == .server {
                Text("Servers don't need a player name.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let message = app.settings.memoryValidationMessage {
                OrzMCBanner("Invalid memory setting: \(message)", role: .error)
            }

            Divider()

            Button("More Settings…") {
                isPresented = false
                openSettings()
            }
            .controlSize(.small)
        }
        .padding(16)
        .frame(width: 320)
    }

    private var usernameBinding: Binding<String> {
        Binding(get: { app.username }, set: { app.username = $0 })
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
}
