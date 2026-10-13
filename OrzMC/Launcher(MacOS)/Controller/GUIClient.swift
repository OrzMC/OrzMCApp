//
//  GUIClient.swift
//  OrzMC
//
//  Created by joker on 2022/10/22.
//

import Foundation
import JokerKits
import Game

struct GUIClient: Client  {
    
    var clientInfo: Game.ClientInfo
    
    let progressHandler: LaunchProgressHandler
    
    mutating func start() async throws {
        
        // 下载启动器启动所需要的文件、资源及依赖
        try await self.download()
        
        // 分析参数并启动客户端
        try await self.launch()
    }
    
    /// 下载启动器启动需要的文件
    mutating func download() async throws {
        let downloadItems = try await generateDownloadItemInfos()
        var progress = 0.0
        var count = 0
        let total = downloadItems.count
        for try await _ in downloadItems.asyncSequence {
            count += 1
            let curProgress = Double(count) / Double(total)
            let delta = curProgress - progress
            if delta > 0.01 || curProgress == 1 {
                progress = curProgress
                await progressHandler(progress)
            }
        }
    }
    
    /// 启动客户端
    mutating func launch() async throws {
        guard let args = try await parseBootArgs() else {
            return
        }
        // 客户端启动后，可以从UI界面关闭，所以可以异步启动
        let gameDir = GameDir.client(version: clientInfo.version.id).dirPath
        // 托管 JRE（B5）：不依赖系统 java。
        let major = await JavaRuntime.javaMajor(forMCVersion: clientInfo.version.id)
        let javaExecutable = try await JavaRuntime.ensure(root: GameDir.root, major: major)
        try Shell.run(path: javaExecutable, args: args, workDirectory: gameDir, terminationHandler: { process in
            guard process.terminationStatus == 0 else {
                return
            }
        })
    }
}
