//
//  AppModel.swift
//  OrzMC
//

import Foundation
import Game
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
    let plugins: PluginDownloadModel
    let console: ServerConsoleModel

    /// 统一错误出口（保留规范错误码，UI 显示「人话 (E_XXX)」）。
    var error: LauncherError?

    init(settings: SettingsModel = SettingsModel()) {
        self.settings = settings
        self.catalog = VersionCatalogModel()
        self.launch = LaunchModel()
        self.servers = ServerRegistryModel()
        self.java = JavaRuntimeModel()
        self.plugins = PluginDownloadModel()
        self.console = ServerConsoleModel()

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
                        try await launch.startClient(
                            version: version,
                            username: username,
                            clientType: settings.clientType,
                            rootDir: settings.rootDir,
                            minMem: settings.minMem,
                            maxMem: settings.maxMem
                        )
                    case .server:
                        let console = self.console
                        let logHandler: @Sendable (String) -> Void = { chunk in
                            console.append(chunk)
                        }
                        if let session = try await launch.startServer(
                            version: version,
                            software: settings.serverSoftware,
                            rootDir: settings.rootDir,
                            minMem: settings.minMem,
                            maxMem: settings.maxMem,
                            enableJVMDebugger: settings.enableJVMDebugger,
                            jvmDebuggerArgs: settings.jvmDebuggerArgs,
                            onServerLog: logHandler
                        ) {
                            servers.record(session.launched)
                            console.attach(
                                session.process,
                                label: "\(version.id) \(settings.serverSoftware.rawValue)"
                            )
                            watchServerExit(session)
                        }
                    }
                }
            } catch {
                launch.resetProgress()
                self.error = LauncherError.wrap(error, fallbackCode: "E_RUNTIME")
            }
        }
    }

    /// 服务端退出后解绑控制台并刷新进程视图（避免"日志还在、进程早没了"）。
    private func watchServerExit(_ session: LaunchedServerSession) {
        let console = self.console
        let servers = self.servers
        let launched = session.launched
        Task {
            let code = await session.process.waitForExit()
            console.detach(reason: "Server exited (code \(code))")
            servers.remove(versionId: launched.versionId, software: launched.software)
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

    func stopAllServers() {
        do {
            try servers.stopAll()
        } catch {
            self.error = LauncherError.wrap(error, fallbackCode: "E_RUNTIME")
        }
    }

    func stopServer(software: SettingsModel.ServerSoftware) {
        guard let version = catalog.selected else { return }
        do {
            try servers.stop(versionId: version.id, software: software)
        } catch {
            self.error = LauncherError.wrap(error, fallbackCode: "E_RUNTIME")
        }
    }

    // MARK: 插件下载

    func downloadAllServerPlugins() {
        guard let version = catalog.selected else { return }
        Task {
            do {
                try await plugins.downloadAll(versionId: version.id)
            } catch {
                self.error = LauncherError.wrap(error, fallbackCode: "E_NETWORK")
            }
        }
    }
}
