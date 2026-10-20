//
//  MCSLPPacket.swift
//  OrzMCTool
//
//  Created by joker on 2019/6/10.
//  Copyright © 2019 joker. All rights reserved.
//
//  Reference:
//      - [Data Types](https://wiki.vg/Protocol#Data_types)
//      - [Packet Format](https://wiki.vg/Protocol#Packet_format)


import Foundation

class MCSLPPacket {
    
    var data: Data {
        return Data(bytes)
    }
    
    private var bytes =  [UInt8]()
    private var current: Int = 0
    
    private func readByte() -> UInt8? {
        
        guard current >= 0 && current < bytes.count else {
            return nil
        }
        
        let byte = bytes[current]
        current += 1
        return byte
    }
    
    private func writeByte(byte: UInt8) {
        bytes.append(byte)
    }
    
    private func writeUnsignedInteger<T: UnsignedInteger>(value: T) {
        var count = value.bitWidth / UInt8.bitWidth
        var innderValue = value
        var bigEndian = [UInt8]()
        repeat {
            let byte = UInt8(innderValue & 0xFF)
            bigEndian.insert(byte, at: 0)
            innderValue >>= UInt8.bitWidth
            count -= 1
        } while(count > 0)
        bytes.append(contentsOf: bigEndian)
    }
    
    private func getVarIntBytes<T: UnsignedInteger>(value: T) -> [UInt8] {
        var ret = [UInt8]()
        var innerValue = value
        repeat {
            var temp: UInt8 = (UInt8)(innerValue & 0b01111111)
            innerValue >>= 7
            if (innerValue != 0) {
                temp |= 0b10000000
            }
            ret.append(temp)
        } while (innerValue != 0)
        return ret
    }
    
    init(data: Data = Data()) {
        let bytes = [UInt8](data)
        self.bytes = bytes
        self.current = 0
    }
    
    func encapsulate() {
        let packetLenBytes = getVarIntBytes(value: UInt(self.bytes.count))
        self.bytes.insert(contentsOf: packetLenBytes, at: 0)
    }
    
    func description() -> String {
        return bytes.map({String($0, radix: 2)}).joined(separator: " ")
    }
}

extension MCSLPPacket {
    
    func readID() -> UInt8? {
        return  readByte()
    }
    
    func writeID(_ id: UInt8) {
        writeByte(byte: id)
    }
    
    func readVarInt() throws -> Int32 {
        var numRead: Int = 0
        var result: Int32 = 0
        var read: UInt8
        repeat {
            guard let nextByte = readByte() else {
                throw MCSLPError.packetMalFormat
            }
            read = nextByte
            let value = (read & 0b01111111)
            result |= Int32((value << (7 * numRead)))
            
            numRead += 1
            if (numRead > 5) {
                throw MCSLPError.VarIntTooBig
            }
        } while ((read & 0b10000000) != 0)
        
        return result
    }
    
    func writeVarInt(value: Int32) {
        let unsignedInteger = UInt32(truncatingIfNeeded: value)
        let bytes = getVarIntBytes(value: unsignedInteger)
        self.bytes.append(contentsOf: bytes)
    }
    
    
    
    func writeString(value: String) {
        if let data = value.data(using: .utf8) {
            let size = Int32(data.count)
            writeVarInt(value: size)
            bytes.append(contentsOf: data)
        }
    }
    
    func readString() throws -> String? {
        let length = try readVarInt()
        guard length >= 0 else {
            throw MCSLPError.packetMalFormat
        }
        let end = current + Int(length)
        guard end <= bytes.count else {
            throw MCSLPError.packetMalFormat
        }
        let ret = String(bytes: bytes[current..<end], encoding: .utf8)
        current = end
        return ret
    }
    
    func writeUnsignedShort(value: UInt16) {
        writeUnsignedInteger(value: value)
    }
    
    func writeLong(value: Int64) {
        let innerValue = UInt64(truncatingIfNeeded: value)
        writeUnsignedInteger(value: innerValue)
    }
}


extension MCSLPPacket: Equatable {
    
    static func == (lhs: MCSLPPacket, rhs: MCSLPPacket) -> Bool {
        guard lhs.data.count == rhs.data.count else {
            return false
        }
        
        for (index, byte) in lhs.data.enumerated() {
            if byte != rhs.data[index] {
                return false
            }
        }
        return true
    }
    
    
}
