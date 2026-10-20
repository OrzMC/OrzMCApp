//
//  MCServerStatus.swift
//  OrzMCTool
//
//  Created by joker on 2019/5/23.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation


/// Minecraft服务器基本信息数据
public struct MCServerBasicStatus {
    let MOTD: String
    let gameType: String
    let map: String
    let numplayers: String
    let maxplayers: String
    let hostport: Int16
    let hostip: String
}

/// Minecraft服务器详细信息数据
public struct MCServerFullStatus {
    let hostname: String
    let gameType: String
    let gameId: String
    let version: String
    let plugins: String
    let map: String
    let numplayers: String
    let maxPlayers: String
    let hostPort: String
    let hostIP: String
    let players: [String]
}

