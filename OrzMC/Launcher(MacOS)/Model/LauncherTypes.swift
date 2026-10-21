//
//  LauncherTypes.swift
//  OrzMC
//
//  Created by Codex on 2026/5/23.
//

import Game
import JokerKits

/// 引擎传出的**结构化进度**（count/bytes、不定长、阶段标题），GUI 用它驱动进度 UI。
typealias LaunchProgressHandler = @Sendable (LaunchProgress) async -> Void

typealias ServerPluginDownloadProgressHandler = @Sendable (ServerPluginDownloadProgress) async -> Void

struct ServerPluginDownloadProgress: Equatable {
    let title: String
    let fraction: Float
}

struct LaunchedServer {
    let versionId: String
    let software: SettingsModel.ServerSoftware
    let pid: String
}

/// 已启动的服务端会话：登记信息 + **进程句柄**（控制台要它送命令/等退出）。
struct LaunchedServerSession {
    let launched: LaunchedServer
    let process: ManagedProcess
}
