//
//  MCSLPStatus.swift
//  OrzMCTool
//
//  Created by joker on 2019/6/12.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation

struct MCSLPStatus: Codable {
    
    struct Description: Codable {
        let text: String
    }
    
    struct Players: Codable {
        let max: Int
        let online: Int
    }
    
    struct Version: Codable {
        let name: String
        let `protocol`: Int
    }
    
    let description: MCSLPStatus.Description
    let players: MCSLPStatus.Players
    let version: MCSLPStatus.Version
    let favicon: String
}


