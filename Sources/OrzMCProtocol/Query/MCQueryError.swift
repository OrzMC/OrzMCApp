//
//  MCQueryError.swift
//  OrzMCTool
//
//  Created by wangzhizhou on 2020/9/3.
//  Copyright © 2020 joker. All rights reserved.
//

import Foundation

enum MCQueryError: Error {
    case socketCreateFailed
    case handshakeFailed
    case readBasicStatusFailed
    case readFullStatusFailed
}
