//
//  MCRCON.swift
//  OrzMCTool
//
//  Created by joker on 2019/6/12.
//  Copyright © 2019 joker. All rights reserved.
//
//  Reference:
//      - [RCON](https://wiki.vg/RCON)
//      - [Source RCON Protocol](https://developer.valvesoftware.com/wiki/Source_RCON_Protocol)
//      - RCON使用TCP
//

import Foundation
import Socket

open class MCRCON {

    /// Minecraft服务器默认RCON服务端口
    static let defaultRCONPort: Int32 = 25575
    
    /// 主机地址/域名
    var host: String

    /// 端口号
    var port: Int32
    
    /// TCPSocket 客户端
    lazy var client: Socket? = {
        return try? Socket.create(family: .inet, type: .stream, proto: .tcp)
    }()
    
    /// 请求 ID
    var requestID: Int32
    
    /// 初始化MCRCON实例
    /// - Parameters:
    ///   - host: Minecraft 服务端的主机地址可以是域名或者IP格式
    ///   - port: 米呢craft RCON服务所在的端口号
    init(host: String, port: Int32 = MCRCON.defaultRCONPort) {
        self.host = host
        self.port = port
        self.requestID = 0
    }
    
    /// 连接Minecraft 服务端RCON服务，并发送Socket命令
    /// - Parameters:
    ///   - password: RCON服务访问认证密码
    ///   - cmd: 发送给RCON服务的 Minecraft控制台命令
    /// - Throws: 发生错误时会抛出异常供上层处理
    /// - Returns: 通过RCON服务执行Minecraft控制台命令的执行结果返回
    func loginAndSendCmd(password: String, cmd: String) throws -> String? {
        
        guard let client = self.client else {
            throw MCRCONError.socketCreateFailed
        }
        
        if !client.isConnected {
            try client.connect(to: self.host, port: self.port)
        }
        
        let loginPacket = RCONPacket(id: nextRequestID(), type: .auth, body: password)
        try client.write(from: loginPacket.data)
        
        var data = Data()
        let bytesCount = try client.read(into: &data)
        if bytesCount > 0, let response = RCONPacket(data: data) {
            guard response.id == loginPacket.id, response.type == .command else {
                throw MCRCONError.authFailed
            }
            let result = try self.sendCmd(cmd)
            return result
        } else {
            throw MCRCONError.packetMalFormat
        }
    }
    
    /// 发RCON服务发送Minecraft控制台命令
    /// - Parameter cmd: Minecraft控制台命令
    /// - Throws: 发生错误时会抛出异常供上层处理
    /// - Returns: 执行Minecraft控制台命令的执行结果返回
    func sendCmd(_ cmd: String) throws -> String? {
        
        guard let client = self.client else {
            throw MCRCONError.socketCreateFailed
        }
        
        let commandPacket = RCONPacket(id: nextRequestID(), type: .command, body: cmd)
        try client.write(from: commandPacket.data)

        var data = Data()
        let bytesCount = try client.read(into: &data)
        if bytesCount > 0, let response = RCONPacket(data: data) {
            guard commandPacket.id == response.id, response.type == .response else {
                throw MCRCONError.responseInvalid
            }
            let result = response.body
            return result
        } else {
            throw MCRCONError.packetMalFormat
        }
    }
    
    deinit {
        client?.close()
    }

    private func nextRequestID() -> Int32 {
        defer {
            requestID &+= 1
        }
        return requestID
    }
}
