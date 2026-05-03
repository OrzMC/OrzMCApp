//
//  GameModel.swift
//  OrzMC
//
//  Created by joker on 4/27/24.
//

import SwiftUI
import Game
import MojangAPI
import JokerKits

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
            progress = 0.0
        }
        didSet {
            fetchGameInfo()
            fetchCurrentJavaMajorVersion()
        }
    }
    
    var username: String = ""
    
    var gameType: GameType = .client {
        willSet {
            guard gameType != newValue
            else {
                return
            }
            progress = 0.0
        }
    }
    
    var progress: Double = 0.0
    
    var isFetchingGameVersions: Bool = false

    var errorMessage: String?
    
    var isClient: Bool { gameType == .client }
    
    var isServer: Bool { gameType == .server }

    var gameInfoMap = [Version: GameVersion]()
    
    var currentJavaMajorVersion: Int?
    
    static var serverPIDMap = [String: String]()
    
    var isShowKillAllServerButton: Bool = false
    
    var serverPluginDownloadProgress: Float = 0
    
    var serverPluginDownloadProgressTitle: String = ""

    var runningServerPids = Set<String>()

    private let javaRuntimeService = JavaRuntimeService()

    private let serverProcessService = ServerProcessService()
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
        case .invalid:
            return .red
        }
    }
    
    var showJavaVersionArea: Bool { currentJavaMajorVersion != nil || selectedGameJavaMajorVersionRequired != nil }
    
    var progressDesc: String {
        return String(format: "%.2f%%", progress * 100)
    }
    
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
            currentMajorVersion: currentJavaMajorVersion,
            requiredMajorVersion: selectedGameJavaMajorVersionRequired
        )
    }
    
    var selectedServerPID: String? {
        guard isServer, let selectedVersion
        else {
            return nil
        }
        return serverPID(versionId: selectedVersion.id, software: settingsModel.serverSoftware)
    }

    func isServerRunning(versionId: String, software: SettingsModel.ServerSoftware) -> Bool {
        guard let pid = serverPID(versionId: versionId, software: software)
        else {
            return false
        }
        return runningServerPids.contains(pid)
    }
}

extension GameModel {
    
    func fetchCurrentJavaMajorVersion() {
        guard let currentJavaVersion = try? OracleJava.currentJDK()?.version,
              let currentJaveMajorVersionSubstring = currentJavaVersion.split(separator: ".").first,
              let currentJavaMajorVersion = Int(String(currentJaveMajorVersionSubstring))
        else {
            return
        }
        self.currentJavaMajorVersion = currentJavaMajorVersion
    }
    
    func fetchGameVersions() async throws {
        versions = try await Mojang.manifest().versions
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
                guard let gameInfo = try await selectedVersion.gameVersion
                else { return }
                await MainActor.run {
                    gameInfoMap[selectedVersion] = gameInfo
                }
            } catch {
                await MainActor.run {
                    errorMessage = "Failed to load game info: \(error.localizedDescription)"
                }
            }
        }
    }
    
    func startGame() {
        guard let selectedVersion
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
                self.progress = 0
                self.errorMessage = "Failed to start \(gameType.rawValue): \(error.localizedDescription)"
            }
        }
    }
    
    func startClient(_ selectedVersion: Version) async throws {
        let clientInfo = ClientInfo(
            version: selectedVersion,
            username: username,
            minMem: "512M",
            maxMem: "2G"
        )
        var launcher = GUIClient(clientInfo: clientInfo, gameModel: self)
        try await launcher.start()
    }
    
    func startServer(_ selectedVersion: Version) async throws {
        var jvmArgs = [String]()
        if settingsModel.enableJVMDebugger, !settingsModel.jvmDebuggerArgs.isEmpty {
            jvmArgs.append(settingsModel.jvmDebuggerArgs)
        }
        let serverInfo = ServerInfo(
            version: selectedVersion.id,
            gui: false,
            debug: false,
            forceUpgrade: false,
            demo: false,
            minMem: "512M",
            maxMem: "2G",
            jvmArgs: jvmArgs,
            onlineMode: false,
            showJarHelpInfo: false,
            jarOptions: nil
        )
        let launcher = GUIServer(
            serverInfo: serverInfo,
            serverType: settingsModel.serverSoftware.gameType,
            selectedVersion: selectedVersion,
            gameModel: self
        )
        guard let process = try await launcher.start()
        else {
            return
        }
        let pid = String(process.processIdentifier)
        GameModel.serverPIDMap[serverKey(versionId: serverInfo.version, software: settingsModel.serverSoftware)] = pid
    }
    
    func checkRunningServer() {
        let pids = (try? Shell.allRunningServerPids()) ?? []
        let running = Set(pids)
        runningServerPids = running
        if !GameModel.serverPIDMap.isEmpty {
            GameModel.serverPIDMap = serverProcessService.filteredPIDMap(GameModel.serverPIDMap, runningPids: running)
        }
        isShowKillAllServerButton = !running.isEmpty
    }
    
    func stopAllRunningServer() {
        Task {
            do {
                try await Shell.stopAll()
                checkRunningServer()
            } catch {
                errorMessage = "Failed to stop servers: \(error.localizedDescription)"
            }
        }
    }

    func serverPID(versionId: String, software: SettingsModel.ServerSoftware) -> String? {
        GameModel.serverPIDMap[serverKey(versionId: versionId, software: software)]
    }

    func stopServer(versionId: String, software: SettingsModel.ServerSoftware) {
        guard let pid = serverPID(versionId: versionId, software: software)
        else {
            return
        }
        do {
            try Shell.runCommand(with: ["kill", pid])
            GameModel.serverPIDMap.removeValue(forKey: serverKey(versionId: versionId, software: software))
            checkRunningServer()
        } catch {
            errorMessage = "Failed to stop server: \(error.localizedDescription)"
        }
    }

    func serverKey(versionId: String, software: SettingsModel.ServerSoftware) -> String {
        serverProcessService.key(versionId: versionId, software: software)
    }

    func updateProgress(_ progress: Double) {
        self.progress = progress
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
            let serverPluginUpdateDirPath = GameDir.serverPluginUpdate(version: version, type: Game.GameType.paper.rawValue).dirPath
            try serverPluginUpdateDirPath.makeDirIfNeed()
            let outputDirFileURL = URL(fileURLWithPath: serverPluginUpdateDirPath)
            serverPluginDownloadProgress = Float.leastNonzeroMagnitude
            let plugin = PaperPlugin()
            let allPlugins = try await plugin.allPlugin()
            var downloadedPluginCount = 0
            let pluginTotalCount = allPlugins.count
            for plugin in allPlugins {
                downloadedPluginCount += 1
                guard let downloadItem = try await plugin.downloadItem(outputFileDirURL: outputDirFileURL, version: nil),
                      let pluginName = plugin.name
                else {
                    continue
                }
                serverPluginDownloadProgressTitle = "\(pluginName)(\(downloadedPluginCount)/\(pluginTotalCount))"
                try await Downloader.download(downloadItem)
                serverPluginDownloadProgress = Float(downloadedPluginCount) / Float(allPlugins.count)
            }
            await Shell.runCommand(with: ["open", outputDirFileURL.path])
            serverPluginDownloadProgress = 0
        } catch {
            serverPluginDownloadProgress = 0
            errorMessage = "Failed to download server plugins: \(error.localizedDescription)"
        }
    }
}
