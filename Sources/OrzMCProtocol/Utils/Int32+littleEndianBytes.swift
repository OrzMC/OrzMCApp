//
//  Int32+littleEndianBytes.swift
//  OrzMCTool
//
//  Created by joker on 2019/6/12.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation

extension Int32 {
    var littleEndianBytes: [UInt8] {
        var ret = [UInt8]()
        var unsignedInteger = UInt32(truncatingIfNeeded: self)
        var count = unsignedInteger.bitWidth / UInt8.bitWidth
        repeat {
            let byte = UInt8(unsignedInteger & 0xFF)
            ret.append(byte)
            unsignedInteger >>= UInt8.bitWidth
            count -= 1
        } while(count != 0)
        return ret
    }
}
