//
//  Int32+BigEndian.swift
//  OrzMCTool
//
//  Created by joker on 2019/5/23.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation

extension Int32 {
    
    /// Int32整数转成大端存储格式的字节数组
    public var bigEndianBytes: [UInt8] {
        var bigEndianBytes = [UInt8]()
        for i in (0 ..< 4).reversed() {
            let byte = UInt8(self >> (UInt8.bitWidth * i) & 0xFF)
            bigEndianBytes.append(byte)
        }
        return  bigEndianBytes
    }
    
    
    /// 将Int32格式的Minecraft Query协议SessionID转换成大端存储格式的字节数组，
    /// 因为Minecraft不处理字节的高4位, 所以使用0x0F屏蔽高4位
    /// 从而获取合法的sessionID字节数组
    public var sessionIDBytes: [UInt8] {
        var bigEndianBytes = [UInt8]()
        for i in (0 ..< 4).reversed() {
            let byte = UInt8(self >> (UInt8.bitWidth * i) & 0x0F)
            bigEndianBytes.append(byte)
        }
        return  bigEndianBytes
    }
}
