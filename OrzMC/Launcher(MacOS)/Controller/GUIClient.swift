//
//  GUIClient.swift
//  OrzMC
//
//  Created by joker on 2022/10/22.
//

import Foundation
import Game

struct GUIClient: Client {

    var clientInfo: Game.ClientInfo

    let progressHandler: LaunchProgressHandler

    mutating func start() async throws {

        // 下载启动器启动所需要的文件、资源及依赖
        try await self.download()

        // 分析参数并启动客户端
        try await self.launch()
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
    mutating func launch() async throws {
        _ = try await launchClient()
    }
}
