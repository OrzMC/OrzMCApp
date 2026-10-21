//
//  BasicInfo.swift
//  OrzMC
//
//  Created by joker on 2024/4/28.
//

import SwiftUI
import MojangAPI
import Game
import JokerKits
import OrzMCDesignSystem
import OrzMCLauncher

struct FormSectionHeader: View {
    typealias ButtonAction = () -> Void

    let title: String
    /// 运行状态（服务端/客户端都有：Running / Stopped / Starting… / Restarting…）。
    var statusText: String?
    var statusDotColor: Color?
    var statusTextColor: Color?
    /// 该实例有操作在进行（启动/停止/重启中）→ **全部按钮禁用**，防连点。
    var isBusy: Bool = false
    /// 生命周期按钮的可用性（`nil` = 该实例不提供生命周期控制，例如客户端）。
    var availability: InstanceActionAvailability?
    /// 打开该实例自己的控制台（客户端 + 四种核心各一个，入口就在自己这一栏）。
    var consoleBtnAction: ButtonAction?
    var consoleIsLive: Bool = false
    /// 启动（无确认）。
    var startBtnAction: ButtonAction?
    /// 重启（先停后起，会断开玩家 → 二次确认）。
    var restartBtnAction: ButtonAction?
    /// 优雅停止（送 `stop` → 让服务端自己存档退出；会断开玩家 → 二次确认）。
    var stopBtnAction: ButtonAction?
    /// 终止进程（`SIGTERM`→`SIGKILL`，可能丢存档 → 二次确认）。
    var terminateBtnAction: ButtonAction?
    /// 删除（**高危**：删文件，不可恢复）——点击后需二次确认。
    var deleteBtnAction: ButtonAction

    var body: some View {
        HStack(spacing: 8) {
            // 左：标题 + 状态
            Text(title)
            if let statusText {
                statusBadge(statusText)
            }

            Spacer(minLength: 12)

            // 右：操作按钮（高危动作带确认，执行中全禁用）
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            HStack(spacing: 10) {
                if let consoleBtnAction {
                    iconButton(
                        "Console",
                        systemImage: consoleIsLive ? "terminal.fill" : "terminal",
                        color: consoleIsLive ? .green : .accentColor,
                        help: consoleIsLive ? "Open \(title) console (running)" : "Open \(title) console",
                        action: consoleBtnAction
                    )
                }
                if let startBtnAction {
                    iconButton(
                        "Start",
                        systemImage: "play.circle",
                        color: .green,
                        help: "Start \(title)",
                        action: startBtnAction
                    )
                    .disabled(!(availability?.canStart ?? true))
                }
                if let restartBtnAction {
                    iconButton(
                        "Restart",
                        systemImage: "arrow.clockwise.circle",
                        color: .blue,
                        help: "Restart \(title) (stop then start — asks for confirmation)",
                        action: restartBtnAction
                    )
                    .disabled(!(availability?.canRestart ?? true))
                }
                if let stopBtnAction {
                    iconButton(
                        "Stop",
                        systemImage: "stop.circle",
                        color: .orange,
                        help: "Stop \(title) gracefully (console `stop` — asks for confirmation)",
                        action: stopBtnAction
                    )
                    .disabled(!(availability?.canStop ?? true))
                }
                if let terminateBtnAction {
                    iconButton(
                        "Terminate",
                        systemImage: "xmark.octagon",
                        color: .red,
                        help: "Terminate \(title) process now (may lose unsaved world data — asks for confirmation)",
                        action: terminateBtnAction
                    )
                    .disabled(!(availability?.canTerminate ?? true))
                }
                iconButton(
                    "Delete",
                    systemImage: "trash",
                    color: .red,
                    help: "Delete \(title) files (asks for confirmation — cannot be undone)",
                    action: deleteBtnAction
                )
                .disabled(!(availability?.canDelete ?? true))
            }
            .disabled(isBusy)
        }
    }

    private func iconButton(
        _ label: String,
        systemImage: String,
        color: Color,
        help: String,
        action: @escaping ButtonAction
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .foregroundStyle(color)
        .help(help)
    }

    private func statusBadge(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor ?? Color.secondary)
                .frame(width: 6, height: 6)
            Text(text)
                .foregroundStyle(statusTextColor ?? Color.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((statusDotColor ?? Color.secondary).opacity(0.12))
        .cornerRadius(8)
    }
}

struct FilePathEntry: View {
    let name: String
    let path: String
    var body: some View {
        HStack {
            Text(name)
                .bold()
                .foregroundStyle(Color.accentColor)
                .padding([.trailing], 5)
            
            Text(path)
                .foregroundStyle(path.isExist() ? Color.primary : Color.red)
            
            if path.isExist() {
                Spacer()
                Button(action: {
                    _ = try? Shell.runCommand(with: ["open", "\(path)"])
                }, label: {
                    Label("Reveal in Finder", systemImage: path.isDirPath() ? "folder" : "doc.plaintext")
                        .labelStyle(.iconOnly)
                })
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
        }
        .help(path)
    }
}
struct BasicInfo: View {

    @Environment(AppModel.self) private var app
    
    /// 待确认的高危操作（删除/停止）——统一入口，点按钮只"排队"，确认后才执行。
    @State private var pendingRisky: RiskyAction?
    /// 正在执行的实例（`版本#实例`）→ 该实例按钮全禁用（防连点）。
    @State private var busyInstanceId: String?
    /// 「停止全部」的二次确认。
    @State private var confirmStopAll = false
    /// 要打开控制台的实例（`版本#核心`）—— 每个服务端实例各自一个控制台。
    @State private var consoleTarget: ConsoleTarget?
    /// 要打开的插件管理面板（绑定到某个版本）。
    @State private var pluginSheet: PluginSheetTarget?
    
    var body: some View {
        Group {
            if app.catalog.selected == nil {
                EmptyContentView(OrzMCContentStates.noVersionSelected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailsForm
            }
        }
        .navigationTitle(app.detailTitle)
        .navigationDestination(item: $consoleTarget) { target in
            consoleView(for: target)
        }
        .sheet(item: $pluginSheet) { target in
            PluginManagerView(versionId: target.versionId)
        }
        .toolbar {
            if app.servers.hasRunning {
                ToolbarItem {
                    Button {
                        // 会断开所有在线玩家 → 二次确认；执行中禁用（防连点）。
                        confirmStopAll = true
                    } label: {
                        Label("Stop All Servers", systemImage: "stop.circle")
                    }
                    .keyboardShortcut(.init(.init("k")), modifiers: .command)
                    .disabled(busyInstanceId != nil)
                    .help("Stop all running Minecraft servers (asks for confirmation)")
                }
            }
        }
        .alert("Stop All Servers?", isPresented: $confirmStopAll) {
            Button("Stop All", role: .destructive) {
                busyInstanceId = "all"
                Task { @MainActor in
                    defer { busyInstanceId = nil }
                    app.stopAllServers()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All running servers receive `stop` and shut down. Players on them will be disconnected.")
        }
        .alert(
            pendingRisky?.confirmTitle ?? "",
            isPresented: Binding(
                get: { pendingRisky != nil },
                set: { if !$0 { pendingRisky = nil } }
            ),
            presenting: pendingRisky
        ) { action in
            Button(action.confirmButtonTitle, role: action.isDestructive ? .destructive : nil) {
                perform(action)
            }
            Button("Cancel", role: .cancel) { pendingRisky = nil }
        } message: { action in
            Text(action.message(selectedVersionId: app.catalog.selected?.id))
        }
    }

    /// 执行已确认的高危操作：期间该实例按钮全禁用（防连点），完成后复位。
    private func perform(_ action: RiskyAction) {
        let instanceId = action.instanceId
        guard busyInstanceId == nil else { return }
        busyInstanceId = instanceId
        pendingRisky = nil

        Task { @MainActor in
            defer { busyInstanceId = nil }
            switch action {
            case let .deleteServer(versionId, software, path):
                try? path.remove()
                app.removeConsole(versionId: versionId, software: software)
                app.catalog.refreshInstallStates()
            case let .deleteClient(versionId, path):
                try? path.remove()
                app.removeClientConsole(versionId: versionId)
                app.catalog.refreshInstallStates()
            case let .stopServer(versionId, software):
                app.control(.stop, versionId: versionId, software: software)
            case let .restartServer(versionId, software):
                app.control(.restart, versionId: versionId, software: software)
            case let .terminateServer(versionId, software):
                app.control(.terminate, versionId: versionId, software: software)
            }
        }
    }

    /// 该服务端实例是否有操作在进行（确认框执行中 或 生命周期操作中）。
    private func isBusy(versionId: String, software: SettingsModel.ServerSoftware) -> Bool {
        busyInstanceId == "\(versionId)#\(software.rawValue)"
            || app.activity(versionId: versionId, software: software).isBusy
    }

    /// 客户端运行状态：以"客户端控制台是否挂着进程"为准（进程退出即解绑）。
    private var clientRunStatus: (text: String, dotColor: Color, textColor: Color) {
        guard let versionId = app.catalog.selected?.id else {
            return ("Unknown", .secondary, .secondary)
        }
        return app.isClientConsoleAttached(versionId: versionId)
            ? ("Running", .green, .green)
            : ("Stopped", .red, .secondary)
    }

    private func consoleView(for target: ConsoleTarget) -> some View {
        let console: ServerConsoleModel = app.console(for: target)
        let title: String = target.title
        return ServerConsoleView(title: title, console: console)
    }

    private var detailsForm: some View {
        Form {
            // 四种核心（Vanilla/Paper/Fabric/Forge）同一份渲染：只显示已存在的目录，
            // 插件管理仅 Paper 有（引擎 `GamePlan.serverPluginDir` 仅对 paper 有意义）。
            ForEach(SettingsModel.ServerSoftware.allCases) { software in
                if let versionId = app.catalog.selected?.id,
                   let serverDirPath = serverDirPath(for: software),
                   serverDirPath.isExist() {
                    let availability = app.availability(versionId: versionId, software: software)
                    let status = statusFor(software: software)
                    Section {
                        FilePathEntry(name: "Game", path: serverDirPath)
                        if software.supportsPlugins,
                           let pluginDirPath = serverPluginDirPath(for: software) {
                            // 插件下载/更新**不再单独占一条目录项**：它是 Plugins 目录的一部分，
                            // 新装进 plugins/、更新进 plugins/update/（见 PluginManagerModel）。
                            PluginDirectoryEntry(
                                pluginsPath: pluginDirPath,
                                updatePath: serverPluginUpdateDirPath(for: software) ?? "",
                                versionId: versionId,
                                onManage: {
                                    pluginSheet = PluginSheetTarget(versionId: versionId)
                                }
                            )
                        }
                    } header: {
                        FormSectionHeader(
                            title: "Server (\(software.rawValue))",
                            statusText: status.text,
                            statusDotColor: status.dotColor,
                            statusTextColor: status.textColor,
                            isBusy: isBusy(versionId: versionId, software: software),
                            availability: availability,
                            consoleBtnAction: {
                                consoleTarget = ConsoleTarget(versionId: versionId, software: software)
                            },
                            consoleIsLive: app.isConsoleAttached(versionId: versionId, software: software),
                            startBtnAction: {
                                app.control(.start, versionId: versionId, software: software)
                            },
                            restartBtnAction: {
                                pendingRisky = .restartServer(versionId: versionId, software: software)
                            },
                            stopBtnAction: {
                                pendingRisky = .stopServer(versionId: versionId, software: software)
                            },
                            terminateBtnAction: {
                                pendingRisky = .terminateServer(versionId: versionId, software: software)
                            },
                            deleteBtnAction: {
                                pendingRisky = .deleteServer(
                                    versionId: versionId,
                                    software: software,
                                    path: serverDirPath
                                )
                            }
                        )
                    }
                }
            }

            if let clientDirPath, clientDirPath.isExist() {
                Section {
                    FilePathEntry(name: "Game", path: clientDirPath)
                } header: {
                    let clientStatus = clientRunStatus
                    FormSectionHeader(
                        title: "Client",
                        statusText: clientStatus.text,
                        statusDotColor: clientStatus.dotColor,
                        statusTextColor: clientStatus.textColor,
                        isBusy: busyInstanceId == "\(app.catalog.selected?.id ?? "")#Client",
                        consoleBtnAction: {
                            guard let versionId = app.catalog.selected?.id else { return }
                            consoleTarget = ConsoleTarget(versionId: versionId, software: nil)
                        },
                        consoleIsLive: app.isClientConsoleAttached(
                            versionId: app.catalog.selected?.id ?? ""
                        ),
                        deleteBtnAction: {
                            guard let versionId = app.catalog.selected?.id else { return }
                            pendingRisky = .deleteClient(versionId: versionId, path: clientDirPath)
                        }
                    )
                }
            }
        }
        .formStyle(.grouped)
        // 目录是否存在会随**文件系统**变化（服务端跑起来会自己建 world/、装插件会建 update/），
        // 不能只在"切换版本"时才算一遍：详情页可见期间每 1.5s 复核一次（只是几次 stat）。
        .task(id: app.catalog.selected?.id) {
            while !Task.isCancelled {
                app.catalog.refreshInstallStates()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }
}

/// 插件目录条目：显示 `plugins/` 与 `plugins/update/`，并给出"管理插件"入口。
///
/// 说明（对齐 Paper 官方更新机制）：**新装 → `plugins/`；更新 → `plugins/update/`**，
/// 后者由服务端在下次启动时自动应用。UI 上把这条规则写在每一行下面，避免用户以为"下载完立刻生效"。
struct PluginDirectoryEntry: View {
    let pluginsPath: String
    let updatePath: String
    let versionId: String
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Plugins")
                    .bold()
                    .foregroundStyle(Color.accentColor)
                    .padding(.trailing, 5)
                Text(pluginsPath)
                    .foregroundStyle(pluginsPath.isExist() ? Color.primary : Color.red)
                Spacer()
                Button(action: onManage) {
                    Label("Manage Plugins", systemImage: "puzzlepiece.extension")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                if pluginsPath.isExist() {
                    Button {
                        _ = try? Shell.runCommand(with: ["open", pluginsPath])
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .help("Reveal in Finder")
                }
            }
            if !updatePath.isEmpty {
                HStack {
                    Text("PluginsUpdate")
                        .bold()
                        .foregroundStyle(Color.accentColor)
                        .padding(.trailing, 5)
                    Text(updatePath)
                        .foregroundStyle(updatePath.isExist() ? Color.primary : Color.secondary)
                    if updatePath.isExist() {
                        Spacer()
                        Button {
                            _ = try? Shell.runCommand(with: ["open", updatePath])
                        } label: {
                            Label("Reveal in Finder", systemImage: "folder").labelStyle(.iconOnly)
                        }
                        .buttonStyle(.plain)
                        .help("Reveal in Finder")
                    }
                }
                Text("Plugin updates are downloaded here and applied by the server on next restart.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// 插件管理面板的目标（`Identifiable` 供 `sheet(item:)` 用）。
struct PluginSheetTarget: Identifiable {
    let versionId: String
    var id: String { versionId }
}

/// 控制台要打开的实例（`Identifiable` 供 `navigationDestination(item:)` 用）。
///
/// `software == nil` 表示**客户端实例**（`版本#Client`）；否则是对应的服务端核心。
struct ConsoleTarget: Identifiable, Hashable {
    let versionId: String
    let software: SettingsModel.ServerSoftware?

    var id: String {
        "\(versionId)#\(software?.rawValue ?? "Client")"
    }

    var title: String {
        "\(versionId) \(software?.rawValue ?? "Client")"
    }
}

extension BasicInfo {

    func statusFor(software: SettingsModel.ServerSoftware) -> (text: String, dotColor: Color, textColor: Color) {
        guard let selectedVersion = app.catalog.selected
        else {
            return ("Unknown", .secondary, .secondary)
        }
        let text = app.serverStatusText(versionId: selectedVersion.id, software: software)
        switch text {
        case "Running": return ("Running", .green, .green)
        case "Stopped": return ("Stopped", .red, .secondary)
        default: return (text, .orange, .orange)   // Starting… / Stopping… / Restarting… / Terminating…
        }
    }
    
    func serverDirPath(for software: SettingsModel.ServerSoftware) -> String? {
        guard let selectedVersion = app.catalog.selected
        else {
            return nil
        }
        return GamePlan.serverDir(version: selectedVersion.id, type: software.gameType)
    }

    func serverPluginDirPath(for software: SettingsModel.ServerSoftware) -> String? {
        guard let selectedVersion = app.catalog.selected
        else {
            return nil
        }
        return GamePlan.serverPluginDir(version: selectedVersion.id, type: software.gameType)
    }

    func serverPluginUpdateDirPath(for software: SettingsModel.ServerSoftware) -> String? {
        guard let selectedVersion = app.catalog.selected
        else {
            return nil
        }
        return GamePlan.serverPluginUpdateDir(version: selectedVersion.id, type: software.gameType)
    }
    
    var clientDirPath: String? {
        guard let selectedVersion = app.catalog.selected
        else {
            return nil
        }
        return GamePlan.clientDir(version: selectedVersion.id)
    }
}


#Preview {
    
    @Previewable
    @State
    var app = AppModel()

    BasicInfo()
        .frame(width: Constants.minWidth - Constants.sidebarWidth, height: Constants.minHeight)
        .environment(app)
}
