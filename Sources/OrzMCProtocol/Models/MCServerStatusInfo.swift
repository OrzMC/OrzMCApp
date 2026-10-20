//
//  MCServerStatusInfo.swift
//  OrzMCTool
//
//  Created by joker on 2019/6/12.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation

struct MCServerStatusInfo {
    var queryServerBasicStatus: MCServerBasicStatus?
    var queryServerFullStatus: MCServerFullStatus?
    var slpServerStatus: MCSLPStatus?
    var ping: Int?
}
