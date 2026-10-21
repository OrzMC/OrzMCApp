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
    /// 插件管理（仅支持插件的核心，如 Paper）。
    var pluginsBtnAction: ButtonAction?
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
                .font(.headline)
            if let statusText {
                statusBadge(statusText)
            }

            Spacer(minLength: 12)

            // 右：操作按钮（高危动作带确认，执行中全禁用）
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            HStack(spacing: 8) {
                if let consoleBtnAction {
                    iconButton(
                        "Console",
                        systemImage: consoleIsLive ? "terminal.fill" : "terminal",
                        color: consoleIsLive ? .green : .accentColor,
                        help: consoleIsLive ? "Open \(title) console (running)" : "Open \(title) console",
                        action: consoleBtnAction
                    )
                }
                if let pluginsBtnAction {
                    iconButton(
                        "Plugins",
                        systemImage: "puzzlepiece.extension",
                        color: .purple,
                        help: "Manage \(title) plugins (install → plugins/, updates → plugins/update/)",
                        action: pluginsBtnAction
                    )
                }
                if startBtnAction != nil || restartBtnAction != nil || stopBtnAction != nil || terminateBtnAction != nil {
                    groupSeparator
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
                groupSeparator
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

    /// 按钮分组之间的一道细线：把「看/管」与「生命周期」与「删除」视觉上分开。
    private var groupSeparator: some View {
        Rectangle()
            .fill(Color.secondary.opacity(0.25))
            .frame(width: 1, height: 12)
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
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background((statusDotColor ?? Color.secondary).opacity(0.12))
        .cornerRadius(8)
    }
}

/// 一条目录：**标题 + 一句说明 + 右侧「打开」按钮**。
///
/// 不显示完整路径：路径前缀（`~/minecraft/versions/…`）人人相同、又长又占地方，
/// 用户真正要的是"这是干什么的" + 一键跳转。路径放在悬停提示里，需要时还能复制。
struct DirectoryRow: View {
    let entry: GameDirectoryEntry

    private var exists: Bool { entry.path.isExist() }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(exists ? Color.accentColor : Color.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.body.weight(.medium))
                    if !exists {
                        Text("not created yet")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }
                Text(entry.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 8)

            Button {
                open()
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(exists ? Color.accentColor : Color.secondary)
            .disabled(!exists)
            .help(exists ? "Open \(entry.path) in Finder" : "\(entry.path) does not exist yet")
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open() }
        .help(entry.path)
    }

    private var symbolName: String {
        switch entry.kind {
        case .root: return "folder"
        case .world: return "globe.asia.australia"
        case .logs: return "doc.text.magnifyingglass"
        case .plugins: return "puzzlepiece.extension"
        case .pluginUpdates: return "arrow.triangle.2.circlepath"
        case .mods: return "shippingbox"
        case .config: return "slider.horizontal.3"
        case .saves: return "bookmark"
        case .resourcePacks: return "paintpalette"
        }
    }

    private func open() {
        guard exists else { return }
        _ = try? Shell.runCommand(with: ["open", entry.path])
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
    /// 详情页当前查看的实例（`版本#核心` / `版本#Client`）—— 四核心+客户端全装时不再一屏铺 5 段。
    @State private var focusedInstance: String?
    
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
            Button("Stop All (graceful)") {
                busyInstanceId = "all"
                Task { @MainActor in
                    defer { busyInstanceId = nil }
                    app.stopAllServers()
                }
            }
            Button("Terminate All", role: .destructive) {
                busyInstanceId = "all"
                Task { @MainActor in
                    defer { busyInstanceId = nil }
                    app.terminateAllServers()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("""
            Stop All sends `stop` to every running server, so each one saves and exits normally.             Servers started by a previous app session have no console to talk to — those are left alone.

            Terminate All kills the processes instead (SIGTERM, then SIGKILL). Recent world changes may be lost.
            """)
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
        return ServerConsoleView(title: title, console: console, target: target)
    }

    /// 当前版本是否装了任何东西（都没装时给一句引导，而不是一片空白）。
    private var hasAnyInstall: Bool {
        SettingsModel.ServerSoftware.allCases.contains { software in
            (serverDirPath(for: software)?.isExist() ?? false)
        } || (clientDirPath?.isExist() ?? false)
    }

    /// 已安装的实例（用于顶部切换器；只有 1 个时不显示切换器）。
    private var installedInstances: [DetailInstance] {
        var result: [DetailInstance] = []
        for software in SettingsModel.ServerSoftware.allCases {
            if serverDirPath(for: software)?.isExist() ?? false {
                result.append(DetailInstance(id: "\(app.catalog.selected?.id ?? "")#\(software.rawValue)", title: software.rawValue, software: software))
            }
        }
        if clientDirPath?.isExist() ?? false {
            result.append(DetailInstance(id: "\(app.catalog.selected?.id ?? "")#Client", title: "Client", software: nil))
        }
        return result
    }

    /// 当前聚焦的实例：优先用户选的，其次"正在运行的"，再次第一个。
    private var currentInstance: DetailInstance? {
        let instances = installedInstances
        if let focusedInstance, let match = instances.first(where: { $0.id == focusedInstance }) {
            return match
        }
        return instances.first(where: { isRunning($0) }) ?? instances.first
    }

    /// 该实例是否在运行（服务端看登记表，客户端看控制台是否挂着进程）。
    private func isRunning(_ instance: DetailInstance) -> Bool {
        guard let software = instance.software else {
            return app.isClientConsoleAttached(versionId: instance.versionId)
        }
        return app.servers.isRunning(versionId: instance.versionId, software: software)
    }

    private var detailsForm: some View {
        Form {
            // 顶部实例切换器：四种核心 + 客户端全装时，一次只看一个实例（否则一屏 5 段、每段 3-6 行目录，很挤）。
            let instances = installedInstances
            if instances.count > 1 {
                Section {
                    Picker("Instance", selection: Binding(
                        get: { currentInstance?.id ?? instances[0].id },
                        set: { focusedInstance = $0 }
                    )) {
                        ForEach(instances) { instance in
                            Text(isRunning(instance) ? "\(instance.title) ●" : instance.title).tag(instance.id)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }

            if let instance = currentInstance {
                instanceSection(instance)
            } else {
                Section {
                    Text("Nothing installed for \(app.catalog.selected?.id ?? "this version") yet — press Start in the sidebar to install the client or a server core.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
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

    /// 一个实例的目录清单 + 表头（客户端与服务端同一套渲染，客户端只是没有生命周期按钮）。
    @ViewBuilder
    private func instanceSection(_ instance: DetailInstance) -> some View {
        let entries = instance.software.map { directoryEntries(for: $0) } ?? clientDirectoryEntries()

        Section {
            ForEach(entries, id: \.id) { entry in
                if entry.showsWhenMissing || entry.path.isExist() {
                    DirectoryRow(entry: entry)
                }
            }
        } header: {
            if let software = instance.software {
                let availability = app.availability(versionId: instance.versionId, software: software)
                let status = statusFor(software: software)
                FormSectionHeader(
                    title: "Server (\(software.rawValue))",
                    statusText: status.text,
                    statusDotColor: status.dotColor,
                    statusTextColor: status.textColor,
                    isBusy: isBusy(versionId: instance.versionId, software: software),
                    availability: availability,
                    consoleBtnAction: {
                        consoleTarget = ConsoleTarget(versionId: instance.versionId, software: software)
                    },
                    consoleIsLive: app.isConsoleAttached(versionId: instance.versionId, software: software),
                    pluginsBtnAction: software.supportsPlugins ? {
                        pluginSheet = PluginSheetTarget(versionId: instance.versionId)
                    } : nil,
                    startBtnAction: {
                        app.control(.start, versionId: instance.versionId, software: software)
                    },
                    restartBtnAction: {
                        pendingRisky = .restartServer(versionId: instance.versionId, software: software)
                    },
                    stopBtnAction: {
                        pendingRisky = .stopServer(versionId: instance.versionId, software: software)
                    },
                    terminateBtnAction: {
                        pendingRisky = .terminateServer(versionId: instance.versionId, software: software)
                    },
                    deleteBtnAction: {
                        pendingRisky = .deleteServer(
                            versionId: instance.versionId,
                            software: software,
                            path: entryPath(of: entries)
                        )
                    }
                )
            } else {
                let clientStatus = clientRunStatus
                FormSectionHeader(
                    title: "Client",
                    statusText: clientStatus.text,
                    statusDotColor: clientStatus.dotColor,
                    statusTextColor: clientStatus.textColor,
                    isBusy: busyInstanceId == instance.id,
                    consoleBtnAction: {
                        consoleTarget = ConsoleTarget(versionId: instance.versionId, software: nil)
                    },
                    consoleIsLive: app.isClientConsoleAttached(versionId: instance.versionId),
                    deleteBtnAction: {
                        pendingRisky = .deleteClient(versionId: instance.versionId, path: entryPath(of: entries))
                    }
                )
            }
        }
    }

    /// 删除用的路径：取该实例的根目录（`entries` 的第一条恒为根目录）。
    private func entryPath(of entries: [GameDirectoryEntry]) -> String {
        entries.first(where: { $0.kind == .root })?.path ?? entries.first?.path ?? ""
    }
}

/// 详情页里"一个可查看的实例"（某个服务端核心，或客户端）。
struct DetailInstance: Identifiable {
    let id: String
    let title: String
    /// `nil` = 客户端。
    let software: SettingsModel.ServerSoftware?

    var versionId: String {
        String(id.split(separator: "#").first ?? "")
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

    /// 该核心要展示的常用目录（路径来自引擎 `GamePlan`，标题/说明来自 `GameDirectoryCatalog`）。
    func directoryEntries(for software: SettingsModel.ServerSoftware) -> [GameDirectoryEntry] {
        guard let versionId = app.catalog.selected?.id else { return [] }
        let root = app.settings.rootDir
        let serverDir = GamePlan.serverDir(version: versionId, type: software.gameType, root: root)
        let levelName = ServerProperties.levelName(atServerDir: serverDir)
        return GameDirectoryCatalog.serverEntries(
            softwareId: software.rawValue,
            serverDir: serverDir,
            worldDir: GamePlan.serverWorldDir(
                version: versionId, type: software.gameType, levelName: levelName, root: root
            ),
            logsDir: GamePlan.serverLogsDir(version: versionId, type: software.gameType, root: root),
            pluginsDir: GamePlan.serverPluginDir(version: versionId, type: software.gameType, root: root),
            pluginUpdatesDir: GamePlan.serverPluginUpdateDir(version: versionId, type: software.gameType, root: root),
            modsDir: GamePlan.serverModsDir(version: versionId, type: software.gameType, root: root),
            configDir: GamePlan.serverConfigDir(version: versionId, type: software.gameType, root: root)
        )
    }

    /// 客户端常用目录。
    func clientDirectoryEntries() -> [GameDirectoryEntry] {
        guard let versionId = app.catalog.selected?.id else { return [] }
        let root = app.settings.rootDir
        return GameDirectoryCatalog.clientEntries(
            clientType: app.settings.clientType.rawValue,
            clientDir: GamePlan.clientDir(version: versionId, root: root),
            logsDir: GamePlan.clientLogsDir(version: versionId, root: root),
            savesDir: GamePlan.clientSavesDir(version: versionId, root: root),
            modsDir: GamePlan.clientModsDir(version: versionId, root: root),
            resourcePacksDir: GamePlan.clientResourcePacksDir(version: versionId, root: root)
        )
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
