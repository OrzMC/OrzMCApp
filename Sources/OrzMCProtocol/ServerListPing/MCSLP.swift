//
//  MCSLP.swift
//  OrzMCTool
//
//  Created by joker on 2019/6/10.
//  Copyright © 2019 joker. All rights reserved.
//
//  Reference:
//      - [SLP](https://wiki.vg/Server_List_Ping)
//      - SLP使用TCP链接

import Foundation
import Socket

open class MCSLP {
    
    static let defaultPort: Int32 = 25565
    // 主机地址/域名
    var host: String
    // 端口号
    var port: Int32
    // TCP Socket
    lazy var client: Socket? = {
        try? Socket.create(family: .inet, type: .stream, proto: .tcp)
    }()
    
    /// 初始化一个SLP查询实例
    ///
    /// - Parameters:
    ///   - host: 查询的MC服务器主机，可以是域名或者ip地址
    ///   - port: 端口号
    init(host: String, port: Int32 = MCSLP.defaultPort) {
        self.host = host
        self.port = port
    }
    
    func handshake() throws {
        
        guard let client = self.client else {
            throw MCSLPError.socketCreateFailed
        }
        
        try client.connect(to: self.host, port: self.port)
        let handshakePacket = MCSLPPacket()
        handshakePacket.writeID(0x00)
        handshakePacket.writeVarInt(value: -1)
        handshakePacket.writeString(value: host)
        handshakePacket.writeUnsignedShort(value: UInt16(port))
        handshakePacket.writeVarInt(value: 1)
        handshakePacket.encapsulate()
        try client.write(from: handshakePacket.data)
    }
    
    func status() throws -> (status: String?, ping: Int) {
        
        guard let client = self.client else {
            throw MCSLPError.socketCreateFailed
        }
        
        let requestPacket = MCSLPPacket()
        requestPacket.writeID(0x00)
        requestPacket.encapsulate()
        try client.write(from: requestPacket.data)
        
        var data = Data()
        _ = try client.read(into: &data)
        
        let reponse = MCSLPPacket(data: data)
        // PacketLength
        _ = try reponse.readVarInt()
        // packetID
        guard reponse.readID() != nil else {
            throw MCSLPError.packetMalFormat
        }
        // JSON String
        let jsonStr = try reponse.readString()
        
        let ping = try self.ping()
        
        return (status: jsonStr, ping: ping)
    }
    
    func ping() throws -> Int {
        
        guard let client = self.client else {
            throw MCSLPError.socketCreateFailed
        }
        
        let pingPacket = MCSLPPacket()
        pingPacket.writeID(0x01)
        pingPacket.writeLong(value: Int64.max)
        pingPacket.encapsulate()
        
        let startTime = Date()
        try client.write(from: pingPacket.data)
        
        var data = Data()
        _ = try client.read(into: &data)
        let pongPacket = MCSLPPacket(data: data)
        if pingPacket == pongPacket {
            let milliSeconds = Int(Date().timeIntervalSince(startTime) * 1000)
            return milliSeconds
        } else {
            throw MCSLPError.pingFailed
        }
    }
    
    deinit {
        client?.close()
    }
}
