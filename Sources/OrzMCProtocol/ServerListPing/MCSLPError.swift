//
//  MCSLPError.swift
//  OrzMCTool
//
//  Created by joker on 2019/6/10.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation

public enum MCSLPError: Error, Equatable {
    
    case socketCreateFailed
    case VarIntTooBig
    case packetMalFormat
    case pingFailed
    
}
