//
//  GameLaunchService.swift
//  OrzMC
//
//  Created by Codex on 2026/5/23.
//

import Game
import JokerKits
import MojangAPI

struct GameLaunchService {
    func startClient(
        version: Version,
        username: String,
        clientType: SettingsModel.ClientKind,
        rootDir: String,
        minMem: String,
        maxMem: String,
        progressHandler: @escaping LaunchProgressHandler,
        onClientLog: (@Sendable (String) -> Void)? = nil
    ) async throws -> LaunchedClientSession? {
        // Fabric 客户端必须解析 profile addon（loader 库 + 主类）。
        // 引擎只在 `addon != nil` 时才下载 Fabric 库、替换主类（见 `Client+Fabric`）；
        // 之前 GUI 只传了 `type: .fabric` 却没解析 addon，结果"Fabric 启动 = 原版启动"
        // （CLI 一直是对的：`ClientCommand` 里会 `FabricMeta.resolve`）。
        let addon: ProfileAddon?
        if clientType == .fabric {
            addon = try await FabricMeta.resolve(version: version.id, root: rootDir)
        } else {
            addon = nil
        }

        // 内存/客户端类型来自设置（校验已在 `SettingsModel` 用引擎 `MemorySpec` 做过）。
        let clientInfo = ClientInfo(
            version: version,
            username: username,
            rootDir: rootDir,
            type: clientType.gameType,
            minMem: minMem,
            maxMem: maxMem,
            addon: addon,
            onClientLog: onClientLog
        )
        var launcher = GUIClient(
            clientInfo: clientInfo,
            progressHandler: progressHandler
        )
        guard let process = try await launcher.startWithProcess() else { return nil }
        return LaunchedClientSession(
            versionId: version.id,
            clientType: clientType,
            process: process
        )
    }

    func startServer(
        version: Version,
        software: SettingsModel.ServerSoftware,
        rootDir: String,
        minMem: String,
        maxMem: String,
        enableJVMDebugger: Bool,
        jvmDebuggerArgs: String,
        progressHandler: @escaping LaunchProgressHandler,
        onServerLog: (@Sendable (String) -> Void)? = nil
    ) async throws -> LaunchedServerSession? {
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
            onProgress: { event in Task { await handler(event) } },
            onServerLog: onServerLog
        )
        let launcher = GUIServer(
            serverInfo: serverInfo,
            serverType: software.gameType
        )
        guard let process = try await launcher.start()
        else {
            return nil
        }
        return LaunchedServerSession(
            launched: LaunchedServer(
                versionId: serverInfo.version,
                software: software,
                pid: String(process.processIdentifier)
            ),
            process: process
        )
    }
}
