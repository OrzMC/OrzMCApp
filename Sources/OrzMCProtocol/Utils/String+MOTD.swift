//
//  String+MOTD.swift
//  OrzMCTool
//
//  Created by joker on 2019/5/24.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation

extension String {
    public var MODT: NSAttributedString? {
        var motd = ""
        let sectionChar: Character = "\u{00A7}"
        for index in 0 ..< self.count {
            let curIndex = self.index(self.startIndex, offsetBy: index)
            let char = self[curIndex]
            if char == sectionChar {
                continue
            }
            if curIndex > self.startIndex && self[self.index(curIndex, offsetBy: -1)] == sectionChar {
                continue
            }
            motd.append(char)
        }
        return NSAttributedString(string: motd)
    }
}
