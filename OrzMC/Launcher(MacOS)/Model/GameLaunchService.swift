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
        clientType: SettingsModel.ClientKind,
        rootDir: String,
        minMem: String,
        maxMem: String,
        progressHandler: @escaping LaunchProgressHandler
    ) async throws {
        // 内存/客户端类型来自设置（校验已在 `SettingsModel` 用引擎 `MemorySpec` 做过）。
        let clientInfo = ClientInfo(
            version: version,
            username: username,
            rootDir: rootDir,
            type: clientType.gameType,
            minMem: minMem,
            maxMem: maxMem
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
        rootDir: String,
        minMem: String,
        maxMem: String,
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
            rootDir: rootDir,
            gui: false,
            debug: false,
            forceUpgrade: false,
            demo: false,
            minMem: minMem,
            maxMem: maxMem,
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
