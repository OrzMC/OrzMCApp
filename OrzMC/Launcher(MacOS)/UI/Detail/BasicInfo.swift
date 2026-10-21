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

    let title: LocalizedStringKey
    /// 悬停提示里的纯文本标题（`LocalizedStringKey` 不能直接拼进 String 帮助文案）。
    var helpTitle: String = ""
    /// 运行状态（服务端/客户端都有：Running / Stopped / Starting… / Restarting…）。
    var statusText: String?
    var statusStyle: OrzMCStatusStyle = .idle
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
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            // 左：标题 + 状态（同一套状态徽标，颜色只做辅助，文字始终可读）
            Text(title)
                .font(.headline)
            if let statusText {
                OrzMCStatusBadge(verbatim: statusText, style: statusStyle)
            }

            Spacer(minLength: OrzMCTheme.Spacing.md)

            // 右：操作按钮（高危动作带确认，执行中全禁用）
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            HStack(spacing: OrzMCTheme.Spacing.sm) {
                if let consoleBtnAction {
                    iconButton(
                        "Console",
                        systemImage: consoleIsLive ? "terminal.fill" : "terminal",
                        color: consoleIsLive ? OrzMCTheme.Palette.success : OrzMCTheme.Palette.accent,
                        help: consoleIsLive ? "Open \(helpTitle) console (running)" : "Open \(helpTitle) console",
                        action: consoleBtnAction
                    )
                }
                if let pluginsBtnAction {
                    iconButton(
                        "Plugins",
                        systemImage: "puzzlepiece.extension",
                        color: OrzMCTheme.Palette.accent,
                        help: "Manage \(helpTitle) plugins (install → plugins/, updates → plugins/update/)",
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
                        color: OrzMCTheme.Palette.success,
                        help: "Start \(helpTitle)",
                        action: startBtnAction
                    )
                    .disabled(!(availability?.canStart ?? true))
                }
                if let restartBtnAction {
                    iconButton(
                        "Restart",
                        systemImage: "arrow.clockwise.circle",
                        color: OrzMCTheme.Palette.accent,
                        help: "Restart \(helpTitle) (stop then start — asks for confirmation)",
                        action: restartBtnAction
                    )
                    .disabled(!(availability?.canRestart ?? true))
                }
                if let stopBtnAction {
                    iconButton(
                        "Stop",
                        systemImage: "stop.circle",
                        color: OrzMCTheme.Palette.warning,
                        help: "Stop \(helpTitle) gracefully (console `stop` — asks for confirmation)",
                        action: stopBtnAction
                    )
                    .disabled(!(availability?.canStop ?? true))
                }
                // 「不可逆 / 高危」动作收进溢出菜单：日常操作（Start/Restart/Stop）
                // 留在外面，Terminate/Delete 不再和它们抢同一行。
                if terminateBtnAction != nil || deleteBtnAction != nil {
                    groupSeparator
                    Menu {
                        if let terminateBtnAction {
                            Button(role: .destructive, action: terminateBtnAction) {
                                Label("Terminate…", systemImage: "xmark.octagon")
                            }
                            .disabled(!(availability?.canTerminate ?? true))
                        }
                        if let terminateBtnAction, deleteBtnAction != nil {
                            Divider()
                        }
                        Button(role: .destructive, action: deleteBtnAction) {
                            Label("Delete…", systemImage: "trash")
                        }
                        .disabled(!(availability?.canDelete ?? true))
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .foregroundStyle(OrzMCTheme.Palette.danger)
                    .help("More destructive actions (Terminate / Delete — both ask for confirmation)")
                    .disabled(isBusy)
                }
            }
            .disabled(isBusy)
        }
    }

    /// 按钮分组之间的一道细线：把「看/管」与「生命周期」与「删除」视觉上分开。
    private var groupSeparator: some View {
        Divider()
            .frame(height: 12)
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
        // `.borderless` 保留系统 hover/按下反馈；`.plain` 在 macOS 上几乎没有可点击感。
        .buttonStyle(.borderless)
        .foregroundStyle(color)
        .help(help)
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
                .foregroundStyle(exists ? AnyShapeStyle(OrzMCTheme.Palette.accent) : AnyShapeStyle(.secondary))
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.title)
                        .font(.body.weight(.medium))
                    if !exists {
                        OrzMCTag(String(localized: "not created yet"))
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
            .buttonStyle(.borderless)
            .foregroundStyle(exists ? AnyShapeStyle(OrzMCTheme.Palette.accent) : AnyShapeStyle(.secondary))
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
                        // 确认框只在 `LauncherUI` 维护一份（菜单和这里共用），避免 ⌘K 注册两次。
                        app.wantsStopAllConfirmation = true
                    } label: {
                        Label("Stop All Servers", systemImage: "stop.circle")
                    }
                    .disabled(busyInstanceId != nil || app.isStoppingAll)
                    .help("Stop all running Minecraft servers (asks for confirmation)")
                }
            }
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
            || app.launch.isLaunching
    }

    /// 客户端运行状态：以"客户端控制台是否挂着进程"为准（进程退出即解绑）。
    private var clientRunStatus: (text: String, style: OrzMCStatusStyle) {
        guard let versionId = app.catalog.selected?.id else {
            return (String(localized: "Unknown"), .idle)
        }
        return app.isClientConsoleAttached(versionId: versionId)
            ? (String(localized: "Running"), .running)
            : (String(localized: "Stopped"), .idle)
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
            // 启动配置放在最上面：侧边栏只负责“选版本”，详情页负责“启动 + 管理这个版本”。
            LaunchControls()

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
                if let selected = app.catalog.selected {
                    app.catalog.refreshInstallState(for: selected)
                }
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
                    helpTitle: "Server (\(software.rawValue))",
                    statusText: status.text,
                    statusStyle: status.style,
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
                    helpTitle: "Client",
                    statusText: clientStatus.text,
                    statusStyle: clientStatus.style,
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
struct ConsoleTarget: Identifiable, Hashable, Codable {
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

    func statusFor(software: SettingsModel.ServerSoftware) -> (text: String, style: OrzMCStatusStyle) {
        guard let selectedVersion = app.catalog.selected else {
            return (String(localized: "Unknown"), .idle)
        }
        if let activityText = app.activity(versionId: selectedVersion.id, software: software).localizedStatusText {
            return (activityText, .busy)   // Starting… / Stopping… / Restarting… / Terminating…
        }
        if app.servers.isRunning(versionId: selectedVersion.id, software: software) {
            return (String(localized: "Running"), .running)
        }
        // 停止不是错误：用中性色，红色只留给真正的失败/破坏性操作。
        return (String(localized: "Stopped"), .idle)
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
