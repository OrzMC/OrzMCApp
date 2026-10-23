//
//  AppModel.swift
//  OrzMC
//

import Foundation
import Game
import JokerKits
import MojangAPI
import Observation
import OrzMCLauncher

/// 应用的**组合根**：把「设置 / 版本目录 / 启动 / 服务端登记 / JRE / 插件下载」
/// 六个聚焦模型拼起来，只做编排，不装业务。
///
/// 之前这里是 390 行的 `GameModel`：UI 状态、5 个服务、进度镜像、进程登记全在一个类里，
/// 任何改动都要碰它，也没法测。现在每个关注点一个模型（逻辑下沉到 `Sources/OrzMCLauncher`
/// 便于单测），这里只剩：转发选择变化、启动时按模式分流、把错误收成一处给 UI 弹窗。
@MainActor
@Observable
final class AppModel {

    let settings: SettingsModel
    let catalog: VersionCatalogModel
    let launch: LaunchModel
    let servers: ServerRegistryModel
    let java: JavaRuntimeModel
    let pluginManager: PluginManagerModel
    let consoles: ServerConsoleRegistry

    /// 统一错误出口（保留规范错误码，UI 显示「人话 (E_XXX)」）。
    var error: LauncherError?

    /// **本次运行**启动的服务端进程句柄（`版本#核心` → 进程）。
    ///
    /// 为什么单独存：`servers`（登记表）只有 PID，够探活/杀进程；
    /// 但「**优雅停止**」要往 stdin 送 `stop`、重启要等它真的退出 —— 都需要句柄。
    /// App 重启后接管以前启的进程时句柄已经没了，此时只能「终止」，不能「停止」。
    private var serverProcesses: [ConsoleInstanceKey: ManagedProcess] = [:]

    /// 各实例正在进行的生命周期操作（驱动按钮禁用 + 防连点）。
    private(set) var activities: [ConsoleInstanceKey: InstanceActivity] = [:]

    /// 按**客户端类型**记正在运行的进程（控制台仍按版本共用，但"运行中"必须分卡片）。
    private(set) var runningClients: [ConsoleInstanceKey: ManagedProcess] = [:]

    /// 各实例**当前启动进度**（卡片标题区的百分比；与全局 `launch.progress` 同源，但按实例存）。
    private(set) var instanceProgress: [ConsoleInstanceKey: LaunchProgressState] = [:]

    /// 某个实例的启动进度（`nil` = 没在下载/启动）。
    func progress(for key: ConsoleInstanceKey) -> LaunchProgressState? {
        instanceProgress[key]
    }

    /// 客户端实例键（按类型区分：Vanilla / Fabric 是两张卡片）。
    func clientKey(versionId: String, kind: SettingsModel.ClientKind) -> ConsoleInstanceKey {
        ConsoleInstanceKey.client(versionId: versionId, kind: kind.rawValue)
    }

    /// 菜单「停止全部」请求确认（由 `LauncherUI` 弹出同一条确认）。
    var wantsStopAllConfirmation = false

    /// 「停止全部 / 终止全部」进行中：菜单与工具栏按钮统一禁用，避免重复触发。
    private(set) var isStoppingAll = false

    init(settings: SettingsModel = SettingsModel()) {
        self.settings = settings
        self.catalog = VersionCatalogModel()
        self.launch = LaunchModel()
        self.servers = ServerRegistryModel()
        self.java = JavaRuntimeModel()
        self.pluginManager = PluginManagerModel()
        self.consoles = ServerConsoleRegistry()

        catalog.lastSelectedVersionId = settings.lastSelectedVersionId
        catalog.rootDir = settings.rootDir
        java.rootDir = settings.rootDir
        catalog.onSelectionChange = { [weak self] version in
            self?.selectionDidChange(version)
        }
        // 版本详情异步到达后 Java 需求才算得出来：到了就同步一次（标题栏的 Java 状态靠它）。
        catalog.onGameInfoLoaded = { [weak self] in
            self?.syncJavaRequirement()
        }
        // 首个选择可能来自恢复逻辑（此时 onSelectionChange 已就位）。
        if let restored = catalog.selected { selectionDidChange(restored) }
    }

    // MARK: 选择

    var gameMode: GameMode {
        get { settings.gameMode }
        set {
            guard settings.gameMode != newValue else { return }
            settings.gameMode = newValue
            launch.resetProgress()
        }
    }

    var selectedVersion: Version? { catalog.selected }

    /// 游戏根目录（多实例）：改根要重算"装了什么"、重置 JRE 与进程视图。
    var rootDir: String {
        get { settings.rootDir }
        set {
            guard settings.rootDir != newValue else { return }
            settings.rootDir = newValue
            catalog.rootDir = newValue
            java.rootDir = newValue
            java.refresh()
            servers.refresh()
            launch.resetProgress()
        }
    }

    var isRootDirValid: Bool { settings.isRootDirValid }

    /// 模式的展示名（`GameMode.title` 是引擎层英文，UI 这里本地化）。
    var localizedGameModeTitle: String {
        gameMode == .client ? String(localized: "Client") : String(localized: "Server")
    }

    var detailTitle: String {
        guard let selected = catalog.selected else { return "Minecraft" }
        return "Minecraft - \(selected.id)"
    }

    /// 把「当前版本需要哪个 Java」同步到 JRE 模型（选择变化 / gameInfo 到达时都调）。
    private func syncJavaRequirement() {
        java.requiredMajor = catalog.requiredJavaMajor(for: catalog.selected)
    }

    /// 用户名（离线）：存在设置里，下次启动预填。
    var username: String {
        get { settings.username }
        set { settings.username = newValue }
    }

    private func selectionDidChange(_ version: Version) {
        settings.lastSelectedVersionId = version.id
        syncJavaRequirement()
        java.refresh()
        launch.resetProgress()
        servers.refresh()
    }

    // MARK: 启动

    /// 当前模式的实例是否已经在运行（客户端看控制台是否挂着进程；服务端看登记表）。
    ///
    /// 侧边栏的 Start 按钮和 Game 菜单都用它做前置条件，避免“点两次启动两个客户端/
    /// 两个服务端”（服务端第二次会撞端口）。
    var isCurrentInstanceRunning: Bool {
        guard let version = catalog.selected else { return false }
        switch gameMode {
        case .client:
            return isClientConsoleAttached(versionId: version.id, kind: settings.clientType)
        case .server:
            return servers.isRunning(versionId: version.id, software: settings.serverSoftware)
        }
    }

    var canStart: Bool {
        guard catalog.selected != nil,
              !catalog.isLoading,
              !launch.isLaunching,
              settings.isMemoryValid,
              !isCurrentInstanceRunning
        else {
            return false
        }
        if gameMode == .client {
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    /// 按当前模式启动（客户端/服务端），错误统一进 `error`。
    func start() {
        guard canStart, let version = catalog.selected else { return }
        let mode = gameMode
        let settings = self.settings

        Task {
            do {
                try await launch.withLaunching {
                    switch mode {
                    case .client:
                        // 客户端实例也有自己的控制台（key = `版本#Client`）。
                        // **一切按"卡片"记**：两种客户端各有一张卡、一个控制台。
                        let cardKey = clientKey(versionId: version.id, kind: settings.clientType)
                        let key = cardKey
                        activities[cardKey] = .starting
                        defer {
                            activities[cardKey] = nil
                            instanceProgress[cardKey] = nil
                        }
                        launch.progressObserver = { [weak self] state in
                            self?.instanceProgress[cardKey] = state
                        }
                        defer { launch.progressObserver = nil }
                        // 标记"这种客户端类型在这个版本下被启动过"：
                        // Vanilla/Fabric 共用同一个目录，详情页靠它决定显示哪张卡。
                        ClientKindMarkers.mark(
                            clientDir: GamePlan.layout(root: settings.rootDir, version: version.id).clientDir,
                            kind: settings.clientType.rawValue
                        )
                        let console = consoles.model(for: key)
                        let logHandler: @Sendable (String) -> Void = { chunk in
                            console.append(chunk)
                        }
                        if let session = try await launch.startClient(
                            version: version,
                            username: username,
                            clientType: settings.clientType,
                            rootDir: settings.rootDir,
                            minMem: settings.minMem,
                            maxMem: settings.maxMem,
                            onClientLog: logHandler
                        ) {
                            consoles.attach(session.process, to: key)
                            runningClients[cardKey] = session.process
                            watchClientExit(session, key: key, cardKey: cardKey)
                        }
                    case .server:
                        try await launchServer(version: version, software: settings.serverSoftware)
                    }
                }
            } catch {
                launch.resetProgress()
                self.error = LauncherError.wrap(error, fallbackCode: "E_RUNTIME")
            }
        }
    }

    // MARK: 服务端生命周期（启动 / 重启 / 停止 / 终止）

    private func key(_ versionId: String, _ software: SettingsModel.ServerSoftware) -> ConsoleInstanceKey {
        ConsoleInstanceKey(versionId: versionId, instanceId: software.rawValue)
    }

    /// 实例当前活动（`idle` = 没在忙）。
    func activity(versionId: String, software: SettingsModel.ServerSoftware) -> InstanceActivity {
        activities[key(versionId, software)] ?? .idle
    }

    /// 客户端**某类型**卡片当前活动（启动过程中为 `.starting`）。
    func clientActivity(versionId: String, kind: SettingsModel.ClientKind) -> InstanceActivity {
        activities[clientKey(versionId: versionId, kind: kind)] ?? .idle
    }

    /// 按钮可用性：结合"是否在跑 / 是否在忙 / 有没有句柄"。
    func availability(versionId: String, software: SettingsModel.ServerSoftware) -> InstanceActionAvailability {
        InstanceActionAvailability.make(
            isRunning: servers.isRunning(versionId: versionId, software: software),
            activity: activity(versionId: versionId, software: software),
            canControlGracefully: serverProcesses[key(versionId, software)] != nil
        )
    }

    /// 启动某个服务端实例（按当前设置的内存/JVM 参数）。
    private func launchServer(version: Version, software: SettingsModel.ServerSoftware) async throws {
        let settings = self.settings
        let key = self.key(version.id, software)
        let console = consoles.model(for: key)
        let logHandler: @Sendable (String) -> Void = { chunk in
            console.append(chunk)
        }
        // 进度进卡片（详情页标题区），启动结束后清掉。
        launch.progressObserver = { [weak self] state in
            self?.instanceProgress[key] = state
        }
        defer {
            launch.progressObserver = nil
            instanceProgress[key] = nil
        }
        if let session = try await launch.startServer(
            version: version,
            software: software,
            rootDir: settings.rootDir,
            minMem: settings.minMem,
            maxMem: settings.maxMem,
            enableJVMDebugger: settings.enableJVMDebugger,
            jvmDebuggerArgs: settings.jvmDebuggerArgs,
            onServerLog: logHandler
        ) {
            serverProcesses[key] = session.process
            servers.record(session.launched)
            consoles.attach(
                session.process,
                to: key,
                label: "\(version.id) \(software.rawValue)"
            )
            watchServerExit(session, key: key)
        }
    }

    /// 执行一个生命周期操作（UI 已经做过二次确认）。
    func control(
        _ action: ServerLifecycleAction,
        versionId: String,
        software: SettingsModel.ServerSoftware
    ) {
        guard case .idle = activity(versionId: versionId, software: software) else { return }
        guard let version = catalog.versions.first(where: { $0.id == versionId }) else { return }
        let key = self.key(versionId, software)

        Task { @MainActor in
            switch action {
            case .start:
                activities[key] = .starting
            case .stop:
                activities[key] = .stopping
            case .terminate:
                activities[key] = .terminating
            case .restart:
                activities[key] = .restarting
            }
            defer { activities[key] = nil }
            do {
                switch action {
                case .start:
                    try await launchServer(version: version, software: software)
                case .stop:
                    await stopServer(versionId: versionId, software: software, force: false)
                case .terminate:
                    await stopServer(versionId: versionId, software: software, force: true)
                case .restart:
                    // 没有句柄 = 上个会话启动的实例：送不进 `stop`，先停也停不下来，
                    // 直接起会撞端口。明确报错，让用户先「终止」。
                    guard serverProcesses[key] != nil else {
                        self.error = LauncherError(
                            code: "E_RUNTIME",
                            message: "This server was started by a previous app session, so it cannot be restarted from here. "
                                + "Terminate it first, then press Start."
                        )
                        return
                    }
                    await stopServer(versionId: versionId, software: software, force: false)
                    try await launchServer(version: version, software: software)
                }
            } catch {
                self.error = LauncherError.wrap(error, fallbackCode: "E_RUNTIME")
            }
        }
    }

    /// 停止/终止：有句柄 → 优雅停止或强制终止；没句柄（App 重启后接管）→ 只能按 PID 杀。
    private func stopServer(
        versionId: String,
        software: SettingsModel.ServerSoftware,
        force: Bool
    ) async {
        let key = self.key(versionId, software)
        if let process = serverProcesses[key] {
            if force {
                await process.terminate()
            } else {
                await process.stop()   // 送 `stop` → 60s → SIGTERM → 5s → SIGKILL
            }
            _ = await process.waitForExit(timeout: 5)
            serverProcesses[key] = nil
        } else if force {
            // 只有 PID：送不进 `stop` → SIGTERM 给 JVM 存档机会，超时再 SIGKILL。
            try? servers.terminate(versionId: versionId, software: software)
        } else {
            // 想优雅停但没有句柄：不动它（静默硬杀更危险）。
            return
        }
        servers.remove(versionId: versionId, software: software)
    }

    /// 服务端退出后解绑控制台并刷新进程视图（避免"日志还在、进程早没了"）。
    private func watchServerExit(_ session: LaunchedServerSession, key: ConsoleInstanceKey) {
        let launched = session.launched
        Task { @MainActor [weak self] in
            let code = await session.process.waitForExit()
            guard let self else { return }
            self.consoles.detach(key, reason: "Server exited (code \(code))")
            self.serverProcesses[key] = nil
            self.servers.remove(versionId: launched.versionId, software: launched.software)
        }
    }

    /// 客户端退出（玩家关掉游戏）后解绑控制台，日志保留。
    private func watchClientExit(
        _ session: LaunchedClientSession,
        key: ConsoleInstanceKey,
        cardKey: ConsoleInstanceKey
    ) {
        let consoles = self.consoles
        Task { @MainActor [weak self] in
            let code = await session.process.waitForExit()
            consoles.detach(key, reason: "Client exited (code \(code))")
            self?.runningClients[cardKey] = nil
        }
    }

    /// 某实例的控制台（视图按实例取；不存在时创建空控制台，便于先看后启动）。
    func console(for versionId: String, software: SettingsModel.ServerSoftware) -> ServerConsoleModel {
        consoles.model(for: ConsoleInstanceKey(versionId: versionId, instanceId: software.rawValue))
    }

    /// 按 `ConsoleTarget` 取控制台（客户端 / 某个服务端核心）。
    func console(for target: ConsoleTarget) -> ServerConsoleModel {
        if let software = target.software {
            return console(for: target.versionId, software: software)
        }
        return clientConsole(
            versionId: target.versionId,
            kind: target.clientKind ?? settings.clientType
        )
    }

    func clientConsole(versionId: String, kind: SettingsModel.ClientKind) -> ServerConsoleModel {
        consoles.model(for: clientKey(versionId: versionId, kind: kind))
    }

    func isClientConsoleAttached(versionId: String, kind: SettingsModel.ClientKind) -> Bool {
        consoles.isAttached(clientKey(versionId: versionId, kind: kind))
    }

    /// 客户端**某类型**是否在运行（Vanilla / Fabric 各算各的）。
    func isClientRunning(versionId: String, kind: SettingsModel.ClientKind) -> Bool {
        runningClients[clientKey(versionId: versionId, kind: kind)] != nil
    }

    func isConsoleAttached(versionId: String, software: SettingsModel.ServerSoftware) -> Bool {
        consoles.isAttached(
            ConsoleInstanceKey(versionId: versionId, instanceId: software.rawValue)
        )
    }

    /// 删除实例文件后清掉对应控制台（日志/历史一并清）。
    func removeConsole(versionId: String, software: SettingsModel.ServerSoftware) {
        consoles.remove(ConsoleInstanceKey(versionId: versionId, instanceId: software.rawValue))
    }

    func removeClientConsole(versionId: String, kind: SettingsModel.ClientKind) {
        consoles.remove(clientKey(versionId: versionId, kind: kind))
    }

    /// 清掉某版本下**所有实例**的控制台（批量删除用）。
    func removeConsoles(versionId: String) {
        for software in SettingsModel.ServerSoftware.allCases {
            consoles.remove(ConsoleInstanceKey(versionId: versionId, instanceId: software.rawValue))
        }
        for kind in SettingsModel.ClientKind.allCases {
            consoles.remove(clientKey(versionId: versionId, kind: kind))
        }
    }

    // MARK: 版本目录

    func loadVersions() async {
        do {
            try await catalog.load()
        } catch {
            self.error = LauncherError.wrap(error, fallbackCode: "E_NETWORK")
        }
    }

    // MARK: 服务端进程

    /// 停止全部：**只做优雅停止**（送控制台 `stop`），不再逐个 `kill`。
    ///
    /// 边界：App 重启后接管的上个会话实例**没有句柄**，送不进 `stop`。对它们不做任何事，
    /// 而是把名字回报给用户 —— 由用户自己决定要不要「终止」（`SIGTERM`→`SIGKILL`）。
    /// 静默硬杀别人的世界比"停下来问一句"危险得多。
    func stopAllServers() {
        guard !isStoppingAll else { return }
        isStoppingAll = true
        Task { @MainActor in
            defer { isStoppingAll = false }
            let running = servers.runningInstances()
            var gracefullyStopped = 0
            var unmanaged: [String] = []
            for instance in running {
                let key = self.key(instance.versionId, instance.software)
                if serverProcesses[key] != nil {
                    await stopServer(versionId: instance.versionId, software: instance.software, force: false)
                    gracefullyStopped += 1
                } else {
                    unmanaged.append("\(instance.versionId) \(instance.software.rawValue)")
                }
            }
            if !unmanaged.isEmpty {
                self.error = LauncherError(
                    code: "E_RUNTIME",
                    message: "Stopped \(gracefullyStopped) server(s) gracefully. "
                        + "These were started by a previous app session, so there is no console to send `stop` to: "
                        + unmanaged.joined(separator: ", ")
                        + ". Use Terminate on them if you need them gone."
                )
            }
        }
    }

    /// 「终止全部」：明确由用户触发时才硬杀（`SIGTERM` → 超时 `SIGKILL`）。
    func terminateAllServers() {
        guard !isStoppingAll else { return }
        isStoppingAll = true
        Task { @MainActor in
            defer { isStoppingAll = false }
            for instance in servers.runningInstances() {
                let key = self.key(instance.versionId, instance.software)
                if let process = serverProcesses[key] {
                    await process.terminate()
                    _ = await process.waitForExit(timeout: 5)
                    serverProcesses[key] = nil
                } else {
                    try? servers.terminate(versionId: instance.versionId, software: instance.software)
                }
                servers.remove(versionId: instance.versionId, software: instance.software)
            }
        }
    }
}


// MARK: - 本地化辅助

/// `InstanceActivity` 的英文文案在 `Sources/OrzMCLauncher` 里（纯逻辑，单测用）；
/// UI 侧单独映射到本地化文案，避免把 Bundle/本地化依赖塞进可测的引擎层。
extension InstanceActivity {
    var localizedStatusText: String? {
        switch self {
        case .idle: return nil
        case .starting: return String(localized: "Starting…")
        case .stopping: return String(localized: "Stopping…")
        case .terminating: return String(localized: "Terminating…")
        case .restarting: return String(localized: "Restarting…")
        }
    }
}
