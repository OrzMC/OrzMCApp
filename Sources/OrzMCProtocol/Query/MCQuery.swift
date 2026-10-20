//
//  MCQuery.swift
//  OrzMCTool
//
//  Created by joker on 2019/5/22.
//  Copyright © 2019 joker. All rights reserved.
//
//  Reference:
//      - [Query](https://wiki.vg/Query)
//      - Query协议使用UDP
//

import Foundation
import Socket

open class MCQuery {
    
    static let defaultQueryPort: Int32 = 25565
    
    // 主机地址/域名
    var host: String
    // 端口号
    var port: Int32
    // UDPSocket 客户端
    lazy var client: Socket? = {
        return try? Socket.create(family: .inet, type: .datagram, proto: .udp)
    }()
    
    // token
    var token: Int32?
    // 会话ID
    var sessionID: Int32
    
    /// 初始化一个MCQuery查询实例
    ///
    /// - Parameters:
    ///   - host: 查询的MC服务器主机，可以是域名或者IP地址
    ///   - port: 端口号
    init(host: String, port: Int32 = MCQuery.defaultQueryPort) {
        self.host = host
        self.port = port
        self.sessionID = 1
    }
    
    /// 与Minecraft服务器进行握手，建立UDP连接
    func handshake() throws {
        
        guard let client = self.client else {
            throw MCQueryError.socketCreateFailed
        }
        
        try client.connect(to: self.host, port: self.port)
        let handshakeRequest = Request(sessionID: self.sessionID)
        try client.write(from: handshakeRequest.packet())
        
        var data = Data()
        let bytesCount = try client.read(into: &data)
        if bytesCount > 0, let response = Response(data), let tokenLatin1String = response.payload.queryString()  {
            let tokenString = tokenLatin1String as NSString
            self.token = tokenString.intValue
        } else {
            throw MCQueryError.handshakeFailed
        }
    }
    
    /// 查询Minecraft服务器基本状态
    open func basicStatus() throws -> MCServerBasicStatus? {
        
        guard let token = self.token else {
            throw MCQueryError.handshakeFailed
        }
        
        guard let client = self.client else {
            throw MCQueryError.socketCreateFailed
        }
        
        let basicStatusRequest = Request(type: .status, sessionID: self.sessionID, payload: token.bigEndianBytes)
        try client.write(from: basicStatusRequest.packet())
        
        var data = Data()
        let bytesCount = try client.read(into: &data)
        if bytesCount > 0, let basicStatus = Response(data)?.parseBasicStatus() {
            return basicStatus
        } else {
            throw MCQueryError.readBasicStatusFailed
        }
    }
    
    
    /// 查询Minecraft服务器详情状态
    open func fullStatus() throws -> MCServerFullStatus? {
        
        guard let token = self.token else {
            throw MCQueryError.handshakeFailed
        }
        
        guard let client = self.client else {
            throw MCQueryError.socketCreateFailed
        }
        
        var payload = [Byte]()
        payload.append(contentsOf: token.bigEndianBytes)
        payload.append(contentsOf: [0x00, 0x00, 0x00, 0x00])
        let fullStatusRequest = Request(type: .status, sessionID: self.sessionID, payload: payload)
        try client.write(from: fullStatusRequest.packet())
        
        var data = Data()
        let bytesCount = try client.read(into: &data)
        if bytesCount > 0, let fullStatus = Response(data)?.parseFullStatus() {
            return fullStatus
        } else {
            throw MCQueryError.readFullStatusFailed
        }
    }
    
    deinit {
        // 关闭Socket UDP连接
        client?.close()
    }
}
