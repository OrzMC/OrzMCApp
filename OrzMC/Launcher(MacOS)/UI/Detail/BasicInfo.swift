//
//  BasicInfo.swift
//  OrzMC
//
//  Created by joker on 2024/4/28.
//

import Game
import JokerKits
import MojangAPI
import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 详情页：当前版本的启动配置 + 实例目录 + 生命周期入口。
///
/// 结构要点（2026-10-22 审查 A1/A2）：
/// - **body 里不做文件 IO**：安装状态来自 `VersionCatalogModel.installStates`，
///   目录清单与「目录是否存在」由下面的刷新任务算好放进 `@State`；
/// - 视图按类型拆分：`FormSectionHeader` / `DirectoryRow` / `InstanceSection` /
///   `DetailInstance` / `ConsoleTarget` / `PluginSheetTarget` 各自成文件。
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
    /// 当前实例的目录清单（由刷新任务填充，body 只读）。
    @State private var entries: [GameDirectoryEntry] = []
    /// `path → 是否存在`（同上：body 里不再逐行 `stat`）。
    @State private var entryExists: [String: Bool] = [:]

    var body: some View {
        Group {
            if app.catalog.selected == nil {
                EmptyContentView(OrzMCContentStates.noVersionSelected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailsForm
            }
        }
        .onChange(of: app.catalog.selected?.id) {
            consoleTarget = nil
            pluginSheet = nil
            entries = []
            entryExists = [:]
            refreshCurrentInstance()
        }
        // 客户端/服务端、客户端类型、服务端核心任一变化 → 下方信息区跟着换。
        .onChange(of: app.gameMode) { refreshCurrentInstance() }
        .onChange(of: app.settings.clientType) { refreshCurrentInstance() }
        .onChange(of: app.settings.serverSoftware) { refreshCurrentInstance() }
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
                // 删除失败必须说话：以前 `try?` 吞掉后还会把界面刷新成"已删除"。
                guard remove(path) else { return }
                app.removeConsole(versionId: versionId, software: software)
                app.catalog.refreshInstallStates()
                refreshCurrentInstance()
            case let .deleteClient(versionId, path):
                guard remove(path) else { return }
                app.removeClientConsole(versionId: versionId)
                app.catalog.refreshInstallStates()
                refreshCurrentInstance()
            case let .stopServer(versionId, software):
                app.control(.stop, versionId: versionId, software: software)
            case let .restartServer(versionId, software):
                app.control(.restart, versionId: versionId, software: software)
            case let .terminateServer(versionId, software):
                app.control(.terminate, versionId: versionId, software: software)
            }
        }
    }

    /// 删除目录；失败时把原因交给全局错误提示并中止后续状态刷新。
    private func remove(_ path: String) -> Bool {
        guard !path.isEmpty else {
            app.error = LauncherError(code: "E_IO", message: String(localized: "The instance folder is not known yet."))
            return false
        }
        do {
            try path.remove()
            return true
        } catch {
            app.error = LauncherError(
                code: "E_IO",
                message: String(localized: "Could not delete the folder. \(error.localizedDescription)")
            )
            return false
        }
    }

    /// 该服务端实例是否有操作在进行（确认框执行中 或 生命周期操作中）。
    private func isBusy(versionId: String, software: SettingsModel.ServerSoftware) -> Bool {
        busyInstanceId == "\(versionId)#\(software.rawValue)"
            || app.activity(versionId: versionId, software: software).isBusy
            || app.launch.isLaunching
    }

    private func consoleView(for target: ConsoleTarget) -> some View {
        ServerConsoleView(
            title: target.title,
            console: app.console(for: target),
            target: target
        )
    }

    /// 当前模式的实例：客户端就是 `版本#Client`，服务端是当前选中的核心。
    /// 详情页按「客户端 / 服务端」切换，不再有 5 路实例分段控件。
    private var currentInstance: DetailInstance? {
        guard let versionId = app.catalog.selected?.id else { return nil }
        if app.gameMode == .client {
            return DetailInstance(
                id: "\(versionId)#Client",
                title: "Client (\(app.settings.clientType.rawValue))",
                software: nil
            )
        }
        let software = app.settings.serverSoftware
        return DetailInstance(
            id: "\(versionId)#\(software.rawValue)",
            title: software.rawValue,
            software: software
        )
    }

    private var detailsForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 顶部：当前模式的启动参数（模式切换就在第一行）。
                LaunchControls()

                // 下方：**当前模式**对应的实例信息区（客户端目录 / 该服务端核心的目录与生命周期）。
                if let instance = currentInstance {
                    instanceSection(instance)
                }
            }
            .padding(20)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .focusSection()
        // 目录是否存在会随**文件系统**变化（服务端跑起来会自己建 world/、装插件会建 update/）：
        // 这里每 1.5s 复核一次，并把结果写进 `@State`，让 body 保持"纯渲染"。
        .task(id: app.catalog.selected?.id) {
            while !Task.isCancelled {
                if let selected = app.catalog.selected {
                    app.catalog.refreshInstallState(for: selected)
                }
                refreshCurrentInstance()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    private func instanceSection(_ instance: DetailInstance) -> some View {
        let status = instance.software.map { statusFor(software: $0) } ?? clientRunStatus
        return InstanceSection(
            instance: instance,
            entries: entries,
            entryExists: entryExists,
            rootPath: entries.first(where: { $0.kind == .root })?.path ?? "",
            statusText: status.text,
            statusStyle: status.style,
            isBusy: instance.software.map { isBusy(versionId: instance.versionId, software: $0) }
                ?? (busyInstanceId == instance.id),
            consoleIsLive: instance.software.map {
                app.isConsoleAttached(versionId: instance.versionId, software: $0)
            } ?? app.isClientConsoleAttached(versionId: instance.versionId),
            availability: instance.software.map {
                app.availability(versionId: instance.versionId, software: $0)
            },
            consoleTarget: $consoleTarget,
            pluginSheet: $pluginSheet,
            pendingRisky: $pendingRisky
        )
    }

    /// 重新计算当前实例的目录清单与存在性（**唯一的**文件 IO 入口，只在任务里跑）。
    private func refreshCurrentInstance() {
        guard let instance = currentInstance else {
            entries = []
            entryExists = [:]
            return
        }
        let newEntries = instance.software.map { directoryEntries(for: $0) } ?? clientDirectoryEntries()
        var newExistence: [String: Bool] = [:]
        newExistence.reserveCapacity(newEntries.count)
        for entry in newEntries {
            newExistence[entry.path] = entry.path.isExist()
        }
        if newEntries.map(\.id) != entries.map(\.id) { entries = newEntries }
        if newExistence != entryExists { entryExists = newExistence }
    }
}

/// 客户端运行状态：以"客户端控制台是否挂着进程"为准（进程退出即解绑）。
extension BasicInfo {
    var clientRunStatus: (text: String, style: OrzMCStatusStyle) {
        guard let versionId = app.catalog.selected?.id else {
            return (String(localized: "Unknown"), .idle)
        }
        return app.isClientConsoleAttached(versionId: versionId)
            ? (String(localized: "Running"), .running)
            : (String(localized: "Stopped"), .idle)
    }

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
