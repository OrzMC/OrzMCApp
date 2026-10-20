//
//  String+base64Image.swift
//  OrzMCTool
//
//  Created by joker on 2019/6/12.
//  Copyright © 2019 joker. All rights reserved.
//

import Foundation

extension String {
    var base64EncodedImageData: Data? {
        if let subStr = self.split(separator: ",").last {
            return Data(base64Encoded: String(subStr))
        } else {
            return nil
        }
    }
}
