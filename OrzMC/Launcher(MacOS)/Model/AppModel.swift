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

    /// 菜单「停止全部」请求确认（由 `LauncherUI` 弹出同一条确认）。
    var wantsStopAllConfirmation = false

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

    var detailTitle: String {
        guard let selected = catalog.selected else { return "Minecraft" }
        return "Minecraft - \(selected.id)"
    }

    /// 用户名（离线）：存在设置里，下次启动预填。
    var username: String {
        get { settings.username }
        set { settings.username = newValue }
    }

    private func selectionDidChange(_ version: Version) {
        settings.lastSelectedVersionId = version.id
        java.requiredMajor = catalog.requiredJavaMajor(for: version)
        java.refresh()
        launch.resetProgress()
        servers.refresh()
    }

    // MARK: 启动

    var canStart: Bool {
        guard catalog.selected != nil,
              !catalog.isLoading,
              !launch.isLaunching,
              settings.isMemoryValid
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
                        let key = ConsoleInstanceKey.client(versionId: version.id)
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
                            watchClientExit(session, key: key)
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

    /// 按钮可用性：结合"是否在跑 / 是否在忙 / 有没有句柄"。
    func availability(versionId: String, software: SettingsModel.ServerSoftware) -> InstanceActionAvailability {
        InstanceActionAvailability.make(
            isRunning: servers.isRunning(versionId: versionId, software: software),
            activity: activity(versionId: versionId, software: software),
            canControlGracefully: serverProcesses[key(versionId, software)] != nil
        )
    }

    /// 服务端实例运行状态文案（启动/停止过程中给出"正在…"）。
    func serverStatusText(versionId: String, software: SettingsModel.ServerSoftware) -> String {
        if let override = activity(versionId: versionId, software: software).statusOverride {
            return override
        }
        return servers.isRunning(versionId: versionId, software: software) ? "Running" : "Stopped"
    }

    /// 启动某个服务端实例（按当前设置的内存/JVM 参数）。
    private func launchServer(version: Version, software: SettingsModel.ServerSoftware) async throws {
        let settings = self.settings
        let key = self.key(version.id, software)
        let console = consoles.model(for: key)
        let logHandler: @Sendable (String) -> Void = { chunk in
            console.append(chunk)
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
    private func watchClientExit(_ session: LaunchedClientSession, key: ConsoleInstanceKey) {
        let consoles = self.consoles
        Task {
            let code = await session.process.waitForExit()
            consoles.detach(key, reason: "Client exited (code \(code))")
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
        return clientConsole(versionId: target.versionId)
    }

    func clientConsole(versionId: String) -> ServerConsoleModel {
        consoles.model(for: .client(versionId: versionId))
    }

    func isClientConsoleAttached(versionId: String) -> Bool {
        consoles.isAttached(.client(versionId: versionId))
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

    func removeClientConsole(versionId: String) {
        consoles.remove(.client(versionId: versionId))
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
        Task { @MainActor in
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
        Task { @MainActor in
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
