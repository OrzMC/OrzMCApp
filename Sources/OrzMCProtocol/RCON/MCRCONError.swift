//
//  MCRCONError.swift
//  OrzMCTool
//
//  Created by joker on 2019/6/14.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation

enum MCRCONError: Error {
    case packetMalFormat
    case authFailed
    case responseInvalid
    case socketCreateFailed
}
