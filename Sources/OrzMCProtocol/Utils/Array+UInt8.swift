//
//  Array+UInt8.swift
//  OrzMCTool
//
//  Created by joker on 2019/5/26.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation

extension Array where Element == UInt8 {
    func queryString() -> String? {
        if let latin1String = String(bytes: self, encoding: .isoLatin1) {
            return latin1String.replacingOccurrences(of: "\0", with: "")
        }
        return nil
    }
}
