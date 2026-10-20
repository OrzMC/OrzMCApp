//
//  MCServerInfo+Equatable.swift
//  OrzMC
//
//  Created by joker on 2023/5/22.
//

import Foundation

extension MCServerInfo: Equatable {
    static func == (lhs: MCServerInfo, rhs: MCServerInfo) -> Bool {
        return lhs.host == rhs.host && lhs.port == rhs.port
    }
}
