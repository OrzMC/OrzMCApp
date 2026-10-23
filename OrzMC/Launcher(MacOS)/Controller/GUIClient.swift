//
//  GUIClient.swift
//  OrzMC
//
//  Created by joker on 2022/10/22.
//

import Foundation
import Game
import JokerKits

struct GUIClient: Client {

    var clientInfo: Game.ClientInfo

    let progressHandler: LaunchProgressHandler

    /// 协议要求的 `start()`（与 CLI 一致的签名）。
    mutating func start() async throws {
        _ = try await startWithProcess()
    }

    /// 下载 → 启动，返回**客户端进程句柄**（GUI 客户端控制台用它接日志/等退出）。
    mutating func startWithProcess() async throws -> ManagedProcess? {
        // 下载启动器启动所需要的文件、资源及依赖
        try await self.download()
        // Fabric 附加库：CLI 的 `Launcher.run()` 里有这一步，之前 GUI 漏了 →
        // classpath 里有 loader 主类、库却不在，启动直接失败（或静默跑成原版）。
        let handler = progressHandler
        try await self.downloadFabric(onEvent: { event in
            Task { await handler(event) }
        })
        // 分析参数并启动客户端
        return try await self.launch()
    }

    /// 下载启动器启动需要的文件（共用引擎 `downloadClient`；Phase 4）。
    ///
    /// 进度走**结构化事件**（B8）：GUI 拿得到阶段标题与已下载量（count/bytes），
    /// 不定长时 `fraction == nil`，UI 不应假装 0%。
    mutating func download() async throws {
        let handler = progressHandler
        try await downloadClient(onEvent: { event in
            Task { await handler(event) }
        })
    }

    /// 启动客户端（后台运行，不等待退出）；共用引擎 `launchClient`。
    mutating func launch() async throws -> ManagedProcess? {
        try await launchClient()
    }
}
