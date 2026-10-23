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

/// 详情页：当前版本的**实例内容**（目录 / 控制台 / 插件 / 生命周期）。
///
/// 启动参数（模式 / 类型 / 玩家名 / Java / 启动按钮）在窗口标题栏（`LaunchToolbar`），
/// 正文不再有"启动面板"。
///
/// 结构要点（2026-10-22 审查 A1/A2）：
/// - **body 里不做文件 IO**：安装状态来自 `VersionCatalogModel.installStates`，
///   目录清单与「目录是否存在」由下面的刷新任务算好放进 `@State`；
/// - 视图按类型拆分：`FormSectionHeader` / `DirectoryRow` / `InstanceSection` /
///   `DetailInstance` / `ConsoleTarget` / `PluginSheetTarget` 各自成文件。
struct BasicInfo: View {

    @Environment(AppModel.self) private var app
    @Environment(ShortcutStore.self) private var shortcuts

    /// 待确认的高危操作（删除/停止）——统一入口，点按钮只"排队"，确认后才执行。
    @State private var pendingRisky: RiskyAction?
    /// 详情页内打开控制台页时，⌘← 返回详情（独立窗口那套走 Esc）。
    @State private var consoleBackMonitor: Any?
    /// 正在执行的实例（`版本#实例`）→ 该实例按钮全禁用（防连点）。
    @State private var busyInstanceId: String?
    /// 要打开控制台的实例（`版本#核心`）—— 每个服务端实例各自一个控制台。
    @State private var consoleTarget: ConsoleTarget?
    /// 要打开的插件管理面板（绑定到某个版本）。
    @State private var pluginSheet: PluginSheetTarget?
    /// 展示模式：折叠（默认，只留表头）/ 展开（显示目录行）。记住上次选择。
    @AppStorage("orzmc.detail.allExpanded") private var allExpanded = false
    /// 单栏的折叠/展开覆盖：`实例 id → 是否展开`（点某一栏的标题时写入；切换全局模式时清空）。
    @State private var expansionOverrides: [String: Bool] = [:]

    /// 每个实例的目录清单：`实例 id → [目录]`（由刷新任务填充，body 只读）。
    @State private var entries: [String: [GameDirectoryEntry]] = [:]
    /// 每个实例的 `path → 是否存在`（同上：body 里不再逐行 `stat`）。
    @State private var entryExists: [String: [String: Bool]] = [:]

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
            entries = [:]
            entryExists = [:]
            expansionOverrides = [:]
            refreshInstances()
        }
        // 切「全部折叠 / 全部展开」= 重置所有单栏覆盖，回到统一状态。
        .onChange(of: allExpanded) {
            expansionOverrides = [:]
        }
        // 控制台作为**页面**推入时（不是独立窗口），⌘← 返回详情。
        .onChange(of: consoleTarget != nil) { _, isPushing in
            if isPushing { installConsoleBackShortcut() } else { removeConsoleBackShortcut() }
        }
        .onDisappear { removeConsoleBackShortcut() }
        .navigationTitle(app.detailTitle)
        .navigationDestination(item: $consoleTarget) { target in
            consoleView(for: target)
        }
        .sheet(item: $pluginSheet) { target in
            PluginManagerView(versionId: target.versionId)
        }
        .toolbar {
            if !existingInstancePaths.isEmpty {
                ToolbarItem {
                    Button {
                        pendingRisky = .deleteAllInstances(
                            versionId: app.catalog.selected?.id ?? "",
                            paths: existingInstancePaths
                        )
                    } label: {
                        Label("Delete All Instances", systemImage: "trash")
                    }
                    .disabled(busyInstanceId != nil)
                    .help("Delete every instance folder of this version (asks for confirmation)")
                }
            }

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
                refreshInstances()
            case let .deleteClient(versionId, kind, path):
                guard remove(path) else { return }
                app.removeClientConsole(versionId: versionId, kind: kind)
                app.catalog.refreshInstallStates()
                refreshInstances()
            case let .deleteAllInstances(versionId, paths):
                // 批量删除：逐个删目录（失败的写在 `error` 里），随后清掉对应控制台并刷新卡片。
                var failed: [String] = []
                for path in paths where !remove(path) { failed.append(path) }
                app.removeConsoles(versionId: versionId)
                app.catalog.refreshInstallStates()
                refreshInstances()
                if !failed.isEmpty {
                    app.error = LauncherError(
                        code: "E_IO",
                        message: "Some folders could not be deleted:\n" + failed.joined(separator: "\n")
                    )
                }
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
        // 只看**这个实例**：`launch.isLaunching` 是全局的，启动客户端时会把四个服务端卡片
        // 一起点亮成 loading（实测踩过）。
        busyInstanceId == "\(versionId)#\(software.rawValue)"
            || app.activity(versionId: versionId, software: software).isBusy
    }

    /// 客户端**这张卡片**的忙碌状态（Vanilla / Fabric 各自独立）。
    private func isClientBusy(_ instance: DetailInstance) -> Bool {
        guard let kind = instance.clientKind else { return false }
        return busyInstanceId == instance.id
            || app.clientActivity(versionId: instance.versionId, kind: kind).isBusy
    }

    /// 客户端某张卡片的启动进度（标题区的百分比）。
    private func clientProgress(_ instance: DetailInstance) -> LaunchProgressState? {
        guard let kind = instance.clientKind else { return nil }
        return app.progress(for: app.clientKey(versionId: instance.versionId, kind: kind))
    }

    /// ⌘←：从"详情页内的控制台页"返回详情（`consoleTarget = nil` 触发 pop）。
    private func installConsoleBackShortcut() {
        guard consoleBackMonitor == nil else { return }
        consoleBackMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard consoleTarget != nil else { return event }
            guard !ShortcutEvents.hasSheet, !ShortcutEvents.isComposing else { return event }
            let spec = shortcuts.spec(for: .consoleBack)
            guard ShortcutEvents.matches(event, spec) else { return event }
            consoleTarget = nil
            return nil
        }
    }

    private func removeConsoleBackShortcut() {
        if let consoleBackMonitor { NSEvent.removeMonitor(consoleBackMonitor) }
        consoleBackMonitor = nil
    }

    private func consoleView(for target: ConsoleTarget) -> some View {
        ServerConsoleView(
            title: target.title,
            console: app.console(for: target),
            target: target
        )
    }

    /// **所有**客户端实例（Vanilla / Fabric）：两者共用同一个 `<version>/client` 目录，
    /// 差别只在启动方式与 Fabric 多出来的 `mods/`。
    private var clientInstances: [DetailInstance] {
        guard let versionId = app.catalog.selected?.id else { return [] }
        return DetailInstance.clients(versionId: versionId)
    }

    /// **所有**服务端实例（每个核心一个，目录/控制台/生命周期都各自独立）。
    private var serverInstances: [DetailInstance] {
        guard let versionId = app.catalog.selected?.id else { return [] }
        return DetailInstance.servers(versionId: versionId)
    }

    /// 显示出来的客户端实例：目录存在 **且** 这种类型被启动过。
    ///
    /// Vanilla 与 Fabric 共用 `<version>/client`，只看目录会把两张卡一起放出来
    /// （用户实测：启动 Vanilla 后 Fabric 卡也冒出来）。类型由 `ClientKindMarkers` 决定。
    private var existingClientInstances: [DetailInstance] {
        clientInstances.filter { isExisting($0) && clientKindIsMarked($0) }
    }

    /// 该客户端类型是否在这个版本下被启动过（旧安装走兼容推断）。
    private func clientKindIsMarked(_ instance: DetailInstance) -> Bool {
        guard let kind = instance.clientKind,
              let rows = entries[instance.id],
              let root = rows.first(where: { $0.kind == .root })?.path
        else { return false }
        let kinds = ClientKindMarkers.markedKinds(clientDir: root)
            ?? ClientKindMarkers.legacyKinds(clientDir: root, version: instance.versionId)
        return kinds.contains(kind.rawValue)
    }

    /// 磁盘上确实存在的服务端实例（对应核心目录在）。
    private var existingServerInstances: [DetailInstance] {
        serverInstances.filter(isExisting)
    }

    /// 待批量删除的目录（客户端两种类型共用同一个目录 → 去重）。
    private var existingInstancePaths: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for instance in existingClientInstances + existingServerInstances {
            guard let rows = entries[instance.id],
                  let root = rows.first(where: { $0.kind == .root })?.path,
                  entryExists[instance.id]?[root] == true,
                  seen.insert(root).inserted
            else { continue }
            result.append(root)
        }
        return result
    }

    /// 该实例的根目录是否存在（客户端两种类型共用一个目录，因此会同时出现/消失）。
    private func isExisting(_ instance: DetailInstance) -> Bool {
        guard let rows = entries[instance.id],
              let root = rows.first(where: { $0.kind == .root })?.path
        else { return false }
        return entryExists[instance.id]?[root] ?? false
    }

    private var detailsForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 启动进度与内存校验这类"当下的问题"贴在实例区上方；
                // 正常状态下什么都不显示，正文从实例面板开始。
                // 顶部的启动条：启动目标 / 玩家名（仅客户端）/ Java 状态 / 启动。
                LaunchBar()

                launchFeedback

                // 只列**磁盘上真的存在**的实例：删掉的/还没创建过的卡片不再占位
                //（要创建就启动一次，引擎会就地建好目录，卡片随后出现）。
                if !existingClientInstances.isEmpty {
                    instanceGroup(
                        title: "Client",
                        caption: "Both client types share the same game folder; Fabric adds a mods folder.",
                        instances: existingClientInstances,
                        showsDisplayControls: true
                    )
                }

                if !existingServerInstances.isEmpty {
                    instanceGroup(
                        title: "Server",
                        caption: "Each server core has its own folder, console and lifecycle.",
                        instances: existingServerInstances
                    )
                }

                if existingClientInstances.isEmpty, existingServerInstances.isEmpty {
                    ContentUnavailableView {
                        Label("No instances yet", systemImage: "shippingbox")
                    } description: {
                        Text("Pick a launch target above and press Start — the folder and its cards appear here once created.")
                    }
                    .frame(maxWidth: .infinity)
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
                refreshInstances()
                try? await Task.sleep(for: .seconds(1.5))
            }
        }
    }

    /// 页面顶部只留"设置有问题"这类全局提示。
    ///
    /// 启动/下载进度**不再出现在这里**：那是某个实例的事，应该出现在它自己的卡片标题区
    /// （`InstanceSection.progress`），否则"顶部转圈 + 不知道是谁在启动"。
    @ViewBuilder
    private var launchFeedback: some View {
        if let message = app.settings.memoryValidationMessage {
            OrzMCBanner("Invalid memory setting: \(message)", role: .error)
        }
    }

    /// 展示模式：**两个动作按钮**（图标），点一下就把所有卡片设成同一状态。
    ///
    /// 这里不能用 `Picker` 绑定 `allExpanded`：单栏折叠/展开后 `allExpanded` 没变，
    /// 再点"已经选中的那一档"不会触发 `onChange`，看起来就是"按钮不起作用"（2026-10-22 实测复现）。
    /// 动作按钮每次都显式设置全局值并清空单栏覆盖，任何状态下都有效。
    private var displayModeControls: some View {
        HStack(spacing: 2) {
            modeButton(
                systemImage: "rectangle.compress.vertical",
                label: "Collapse All",
                isActive: !allExpanded && expansionOverrides.isEmpty
            ) {
                allExpanded = false
                expansionOverrides = [:]
            }
            modeButton(
                systemImage: "rectangle.expand.vertical",
                label: "Expand All",
                isActive: allExpanded && expansionOverrides.isEmpty
            ) {
                allExpanded = true
                expansionOverrides = [:]
            }
        }
        .padding(3)
        .background(OrzMCTheme.Palette.subtleFill, in: RoundedRectangle(cornerRadius: OrzMCTheme.Radius.md))
        .help("Collapse or expand every instance card")
    }

    /// 单个模式按钮：图标态，选中档位有底色；单栏覆盖存在时两档都不高亮（= 混合状态）。
    private func modeButton(
        systemImage: String,
        label: LocalizedStringKey,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 22)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: OrzMCTheme.Radius.sm)
                            .fill(OrzMCTheme.Palette.selectionFill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
    }

    /// 一组实例（客户端组 / 服务端组）：组标题 + 一句说明 + 各实例面板。
    private func instanceGroup(
        title: LocalizedStringKey,
        caption: LocalizedStringKey,
        instances: [DetailInstance],
        showsDisplayControls: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 2)

                Spacer(minLength: 0)

                // 「全部折叠 / 全部展开」放在列表最近的地方（页面级动作，但离卡片最近）。
                if showsDisplayControls {
                    displayModeControls
                }
            }

            Text(caption)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.leading, 2)
                .padding(.bottom, 2)

            ForEach(instances) { instance in
                instanceSection(instance)
            }
        }
    }

    private func instanceSection(_ instance: DetailInstance) -> some View {
        let rows = entries[instance.id] ?? []
        let exists = entryExists[instance.id] ?? [:]
        let root = rows.first(where: { $0.kind == .root })?.path ?? ""
        let status = instance.software.map { statusFor(software: $0) } ?? clientRunStatus(for: instance)

        return InstanceSection(
            instance: instance,
            entries: rows,
            entryExists: exists,
            rootPath: root,
            statusText: status.text,
            statusStyle: status.style,
            progress: instance.software.map {
                app.progress(for: ConsoleInstanceKey(versionId: instance.versionId, instanceId: $0.rawValue))
            } ?? clientProgress(instance),
            isCurrentType: isCurrentType(instance),
            isExpanded: isExpanded(instance),
            toggleAction: { expansionOverrides[instance.id] = !isExpanded(instance) },
            isBusy: instance.software.map { isBusy(versionId: instance.versionId, software: $0) }
                ?? isClientBusy(instance),
            consoleIsLive: instance.software.map {
                app.isConsoleAttached(versionId: instance.versionId, software: $0)
            } ?? app.isClientConsoleAttached(
                versionId: instance.versionId,
                kind: instance.clientKind ?? app.settings.clientType
            ),
            availability: instance.software.map {
                app.availability(versionId: instance.versionId, software: $0)
            },
            consoleTarget: $consoleTarget,
            pluginSheet: $pluginSheet,
            pendingRisky: $pendingRisky
        )
    }

    /// 这一栏是否展开：单栏覆盖优先，否则跟随全局模式。
    private func isExpanded(_ instance: DetailInstance) -> Bool {
        expansionOverrides[instance.id] ?? allExpanded
    }

    /// 该实例是不是工具栏「当前启动类型」指向的那个（客户端的 Vanilla/Fabric、服务端的核心各一个）。
    private func isCurrentType(_ instance: DetailInstance) -> Bool {
        if let software = instance.software {
            return software == app.settings.serverSoftware
        }
        return instance.clientKind == app.settings.clientType
    }

    /// 重新计算**所有实例**的目录清单与存在性（**唯一的**文件 IO 入口，只在任务里跑）。
    private func refreshInstances() {
        let all = clientInstances + serverInstances
        guard !all.isEmpty else {
            entries = [:]
            entryExists = [:]
            return
        }

        var newEntries: [String: [GameDirectoryEntry]] = [:]
        var newExistence: [String: [String: Bool]] = [:]
        newEntries.reserveCapacity(all.count)
        newExistence.reserveCapacity(all.count)

        for instance in all {
            let rows = instance.software.map(directoryEntries(for:)) ?? clientDirectoryEntries(kind: instance.clientKind)
            var existence: [String: Bool] = [:]
            existence.reserveCapacity(rows.count)
            for entry in rows {
                existence[entry.path] = entry.path.isExist()
            }
            newEntries[instance.id] = rows
            newExistence[instance.id] = existence
        }
        if newEntries != entries { entries = newEntries }
        if newExistence != entryExists { entryExists = newExistence }
    }
}

/// 客户端运行状态：以"客户端控制台是否挂着进程"为准（进程退出即解绑）。
extension BasicInfo {
    /// 客户端**这张卡片**的运行状态（按类型，不和另一张共享）。
    func clientRunStatus(for instance: DetailInstance) -> (text: String, style: OrzMCStatusStyle) {
        guard let versionId = app.catalog.selected?.id, let kind = instance.clientKind else {
            return (String(localized: "Unknown"), .idle)
        }
        if let activityText = app.clientActivity(versionId: versionId, kind: kind).localizedStatusText {
            return (activityText, .busy)     // 启动中…（与客户端启动是异步的，先给反馈）
        }
        return app.isClientRunning(versionId: versionId, kind: kind)
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

    /// 客户端常用目录（`kind` 决定是否列出 `mods/`；两者共用同一个 `<version>/client`）。
    func clientDirectoryEntries(kind: SettingsModel.ClientKind?) -> [GameDirectoryEntry] {
        guard let versionId = app.catalog.selected?.id else { return [] }
        let root = app.settings.rootDir
        return GameDirectoryCatalog.clientEntries(
            clientType: (kind ?? app.settings.clientType).rawValue,
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
