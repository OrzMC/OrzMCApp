//
//  GameModel.swift
//  OrzMC
//
//  Created by joker on 4/27/24.
//

import SwiftUI
import Game
import MojangAPI
import OrzMCLauncher

@MainActor
@Observable
final class GameModel {
    
    var settingsModel = SettingsModel()
    
    enum GameType: String, CaseIterable {
        case client, server
    }
    
    var versions = [Version]()
    
    var isLaunchingGame: Bool = false
    
    var selectedVersion: Version? {
        willSet {
            guard selectedVersion != newValue
            else {
                return
            }
            resetProgress()
        }
        didSet {
            fetchGameInfo()
            refreshJavaRuntimes()
        }
    }
    
    /// 离线用户名（初值/改动都同步到设置，下次启动预填）。
    var username: String {
        get { settingsModel.username }
        set { settingsModel.username = newValue }
    }
    
    var gameType: GameType = .client {
        willSet {
            guard gameType != newValue
            else {
                return
            }
            resetProgress()
        }
    }
    
    /// 进度 0…1（不定长时保持 0，`progressIsIndefinite` 为真，UI 不画假进度）。
    var progress: Double = 0.0

    /// 结构化进度（B8）：阶段标题 + 已完成/总量（count 或 bytes）。
    var progressTitle: String = ""

    var progressCompleted: Int64 = 0

    var progressTotal: Int64?

    /// 进度单位（items = 文件数，bytes = 字节数），决定文案怎么渲染。
    var progressKind: LaunchProgress.Kind = .items

    var progressIsIndefinite: Bool = false
    
    var isFetchingGameVersions: Bool = false

    /// 结构化错误（**保留规范错误码**，UI 显示"人话 (code)"）。
    var error: LauncherError?

    /// 兼容旧 UI：只要文案。
    var errorMessage: String? {
        get { error?.description }
        set { error = newValue.map { LauncherError(code: "E_RUNTIME", message: $0) } }
    }
    
    var isClient: Bool { gameType == .client }
    
    var isServer: Bool { gameType == .server }

    var canStartGame: Bool {
        guard selectedVersion != nil,
              !isFetchingGameVersions,
              !isLaunchingGame,
              settingsModel.isMemoryValid
        else {
            return false
        }
        if isClient {
            return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return true
    }

    var gameInfoMap = [Version: GameVersion]()
    
    /// 已就位的托管 JRE major（`<root>/java/<major>`，升序）。
    var installedJavaMajorVersions: [Int] = []
    
    var isShowKillAllServerButton: Bool = false
    
    var serverPluginDownloadProgress: Float = 0
    
    var serverPluginDownloadProgressTitle: String = ""

    var runningServerPids = Set<String>()

    private let javaRuntimeService = JavaRuntimeService()

    private let gameCatalogService = GameCatalogService()

    private var serverProcessService = ServerProcessService()

    private let gameLaunchService = GameLaunchService()

    private let serverPluginDownloadService = ServerPluginDownloadService()
}

extension GameModel {
    
    var detailTitle: String {
        guard let selectedVersion
        else {
            return "Minecraft"
        }
        return "Minecraft - \(selectedVersion.id)"
    }
    
    var javaVersionTextColor: Color {
        
        switch javaRuntimeStatus {
        case .unknown:
            return .primary
        case .valid:
            return .green
        case .missing:
            // 未安装不等于错误：启动时会按 B5 自动安装托管 JRE。
            return .orange
        }
    }
    
    var showJavaVersionArea: Bool { selectedGameJavaMajorVersionRequired != nil }
    
    /// 进度文案：有总量时显示「已下载 / 总量」，否则退回百分比或阶段标题。
    var progressDesc: String {
        if let progressTotal, progressTotal > 0 {
            switch progressKind {
            case .bytes:
                return "\(Self.byteText(progressCompleted)) / \(Self.byteText(progressTotal))"
            case .items:
                return "\(progressCompleted) / \(progressTotal)"
            }
        }
        if progress > 0 {
            return String(format: "%.0f%%", progress * 100)
        }
        return progressTitle
    }

    /// 当前阶段说明（下载/安装/启动）；空串表示无。
    var progressStageText: String { progressTitle }
    
    var selectedGameJavaMajorVersionRequired: Int? {
        guard
            let selectedVersion,
            let gameInfo = gameInfoMap[selectedVersion],
            let javaVersion = gameInfo.javaVersion
        else {
            return nil
        }
        return Int(javaVersion.majorVersion)
    }
    
    typealias JavaRuntimeStatus = JavaRuntimeService.Status

    var javaRuntimeStatus: JavaRuntimeStatus {
        javaRuntimeService.status(
            installedMajorVersions: installedJavaMajorVersions,
            requiredMajorVersion: selectedGameJavaMajorVersionRequired
        )
    }

    /// 已安装的托管 JRE 列表文案（如 "17, 21"；空则 "None"）。
    var installedJavaVersionsText: String {
        installedJavaMajorVersions.isEmpty
            ? "None"
            : installedJavaMajorVersions.map(String.init).joined(separator: ", ")
    }
    
    var selectedServerPID: String? {
        guard isServer, let selectedVersion
        else {
            return nil
        }
        return serverProcessService.pid(versionId: selectedVersion.id, software: settingsModel.serverSoftware)
    }

    func isServerRunning(versionId: String, software: SettingsModel.ServerSoftware) -> Bool {
        guard let pid = serverProcessService.pid(versionId: versionId, software: software)
        else {
            return false
        }
        return runningServerPids.contains(pid)
    }
}

extension GameModel {
    
    /// 重新扫描托管 JRE（引擎 `<root>/java/<major>`）——唯一事实源，不再探系统 JDK。
    func refreshJavaRuntimes() {
        installedJavaMajorVersions = javaRuntimeService.installedMajorVersions()
    }
    
    func fetchGameVersions() async throws {
        versions = try await gameCatalogService.fetchVersions()
    }
    
    func fetchGameInfo() {
        guard let selectedVersion
        else {
            return
        }
        
        guard !gameInfoMap.keys.contains(selectedVersion)
        else {
            return
        }
        
        Task {
            do {
                guard let gameInfo = try await gameCatalogService.fetchGameInfo(for: selectedVersion)
                else { return }
                await MainActor.run {
                    gameInfoMap[selectedVersion] = gameInfo
                }
            } catch {
                await MainActor.run {
                    self.error = LauncherError.wrap(
                        error, fallbackCode: "E_NETWORK")
                }
            }
        }
    }
    
    func startGame() {
        guard canStartGame,
              let selectedVersion
        else {
            return
        }
        
        Task {
            self.isLaunchingGame = true
            defer {
                self.isLaunchingGame = false
            }
            
            do {
                switch gameType {
                case .client:
                    try await startClient(selectedVersion)
                case .server:
                    try await startServer(selectedVersion)
                }
            } catch {
                self.resetProgress()
                self.error = LauncherError.wrap(error, fallbackCode: "E_RUNTIME")
            }
        }
    }
    
    func startClient(_ selectedVersion: Version) async throws {
        try await gameLaunchService.startClient(
            version: selectedVersion,
            username: username,
            clientType: settingsModel.clientType,
            minMem: settingsModel.minMem,
            maxMem: settingsModel.maxMem,
            progressHandler: progressHandler
        )
    }
    
    func startServer(_ selectedVersion: Version) async throws {
        guard let launchedServer = try await gameLaunchService.startServer(
            version: selectedVersion,
            software: settingsModel.serverSoftware,
            minMem: settingsModel.minMem,
            maxMem: settingsModel.maxMem,
            enableJVMDebugger: settingsModel.enableJVMDebugger,
            jvmDebuggerArgs: settingsModel.jvmDebuggerArgs,
            progressHandler: progressHandler
        )
        else {
            return
        }
        serverProcessService.record(launchedServer)
    }
    
    /// 探活**自己登记过的**服务端（`kill(pid, 0)`，不起子进程、不误判别人的进程）。
    func checkRunningServer() {
        serverProcessService.refreshAliveness()
        runningServerPids = serverProcessService.aliveRegisteredPids()
        isShowKillAllServerButton = !runningServerPids.isEmpty
    }

    /// 周期探活（2s；仅在确有登记时才是有效工作）。由场景在出现时启动。
    func startMonitoring() async {
        while !Task.isCancelled {
            checkRunningServer()
            try? await Task.sleep(for: .seconds(2))
        }
    }
    
    func stopAllRunningServer() {
        Task {
            do {
                try serverProcessService.stop(processIds: serverProcessService.pids())
                serverProcessService.removeAll()
                checkRunningServer()
            } catch {
                self.error = LauncherError.wrap(error, fallbackCode: "E_RUNTIME")
            }
        }
    }

    func serverPID(versionId: String, software: SettingsModel.ServerSoftware) -> String? {
        serverProcessService.pid(versionId: versionId, software: software)
    }

    func stopServer(versionId: String, software: SettingsModel.ServerSoftware) {
        guard let pid = serverPID(versionId: versionId, software: software)
        else {
            return
        }
        do {
            try serverProcessService.stop(processId: pid)
            serverProcessService.remove(versionId: versionId, software: software)
            checkRunningServer()
        } catch {
            self.error = LauncherError.wrap(error, fallbackCode: "E_RUNTIME")
        }
    }

    func serverKey(versionId: String, software: SettingsModel.ServerSoftware) -> String {
        serverProcessService.key(versionId: versionId, software: software)
    }

    func resetProgress() {
        progress = 0
        progressTitle = ""
        progressKind = .items
        progressCompleted = 0
        progressTotal = nil
        progressIsIndefinite = false
    }

    /// 人类可读字节数（仅 `progressKind == .bytes` 时使用）。
    static func byteText(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    /// 消费引擎的结构化进度（B8）：`fraction == nil` 视为不定长，只更新阶段文案。
    func updateProgress(_ event: LaunchProgress) {
        if let label = event.label, !label.isEmpty {
            progressTitle = label
        }
        progressKind = event.kind
        progressCompleted = event.completed
        progressTotal = event.total
        progressIsIndefinite = event.fraction == nil
        if let fraction = event.fraction {
            progress = fraction
        }
    }

    var progressHandler: LaunchProgressHandler {
        { [weak self] event in
            await MainActor.run {
                self?.updateProgress(event)
            }
        }
    }
    
    func downloadAllServerPlugins() async throws {
        do {
            if (serverPluginDownloadProgress > 0) {
                return
            }
            guard let version = selectedVersion?.id
            else {
                return
            }
            try await serverPluginDownloadService.downloadAllPaperPlugins(
                versionId: version,
                progressHandler: serverPluginDownloadProgressHandler
            )
        } catch {
            serverPluginDownloadProgress = 0
            self.error = LauncherError.wrap(error, fallbackCode: "E_NETWORK")
        }
    }

    var serverPluginDownloadProgressHandler: ServerPluginDownloadProgressHandler {
        { [weak self] progress in
            await MainActor.run {
                self?.serverPluginDownloadProgressTitle = progress.title
                self?.serverPluginDownloadProgress = progress.fraction
            }
        }
    }
}
