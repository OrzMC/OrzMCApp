//
//  GameLaunchService.swift
//  OrzMC
//
//  Created by Codex on 2026/5/23.
//

import Game
import MojangAPI

struct GameLaunchService {
    func startClient(
        version: Version,
        username: String,
        progressHandler: @escaping LaunchProgressHandler
    ) async throws {
        let clientInfo = ClientInfo(
            version: version,
            username: username,
            minMem: "512M",
            maxMem: "2G"
        )
        var launcher = GUIClient(
            clientInfo: clientInfo,
            progressHandler: progressHandler
        )
        try await launcher.start()
    }

    func startServer(
        version: Version,
        software: SettingsModel.ServerSoftware,
        enableJVMDebugger: Bool,
        jvmDebuggerArgs: String,
        progressHandler: @escaping LaunchProgressHandler
    ) async throws -> LaunchedServer? {
        var jvmArgs = [String]()
        if enableJVMDebugger, !jvmDebuggerArgs.isEmpty {
            jvmArgs.append(jvmDebuggerArgs)
        }

        // 引擎的 `ServerInfo.onProgress` 是唯一进度出口（无控制台的前端用它）。
        let handler = progressHandler
        let serverInfo = ServerInfo(
            version: version.id,
            gui: false,
            debug: false,
            forceUpgrade: false,
            demo: false,
            minMem: "512M",
            maxMem: "2G",
            jvmArgs: jvmArgs,
            onlineMode: false,
            showJarHelpInfo: false,
            jarOptions: nil,
            console: nil,
            onProgress: { event in Task { await handler(event) } }
        )
        let launcher = GUIServer(
            serverInfo: serverInfo,
            serverType: software.gameType
        )
        guard let process = try await launcher.start()
        else {
            return nil
        }
        return LaunchedServer(
            versionId: serverInfo.version,
            software: software,
            pid: String(process.processIdentifier)
        )
    }
}
