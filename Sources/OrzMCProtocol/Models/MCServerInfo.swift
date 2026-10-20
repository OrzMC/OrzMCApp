//
//  MCServerInfo.swift
//  OrzMCTool
//
//  Created by joker on 2019/5/24.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation

struct MCServerInfo {
    
    /// 服务主机名
    let host: String
    
    /// 服务端口号
    let port: Int32
    
    /// query服务端品号
    let queryPort: Int32
    
    /// RCON服务端口号
    let rconPort: Int32
    
    /// RCON服务执行结果
    var rconCmdResult: String?
    
    /// 服务状态信息
    var statusInfo: MCServerStatusInfo
    
    
    init(
        host: String,
        port: Int32,
        queryPort: Int32,
        rconPort: Int32,
        statusInfo: MCServerStatusInfo = MCServerStatusInfo()) {
            self.host = host
            self.port = port
            self.queryPort = queryPort
            self.rconPort = rconPort
            self.statusInfo = statusInfo
        }
}
