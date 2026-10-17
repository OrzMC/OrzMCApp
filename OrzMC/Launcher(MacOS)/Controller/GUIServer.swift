//
//  GUIServer.swift
//  OrzMC
//
//  Created by joker on 4/27/24.
//

import Foundation
import Game
import JokerKits

/// GUI 的服务端适配器：**只做「选类型」**。
///
/// 下载 / 部署 / EULA / 启动参数全部交给引擎 `Game/Server/Deploy/*`，与
/// `orzmc server --type {vanilla,paper,fabric,forge}` 是同一份实现——GUI 不再自己
/// 拼下载或跳过 fabric/forge。
struct GUIServer: Server {

    let serverInfo: ServerInfo

    /// 服务端核心类型（vanilla / paper / fabric / forge）。
    let serverType: GameType

    func start() async throws -> ManagedProcess? {
        switch serverType {
        case .vanilla:
            return try await VanillaServer(serverInfo: serverInfo).start()
        case .paper:
            return try await PaperServer(serverInfo: serverInfo).start()
        case .fabric:
            return try await FabricServer(serverInfo: serverInfo).start()
        case .forge:
            return try await ForgeServer(serverInfo: serverInfo).start()
        }
    }
}
