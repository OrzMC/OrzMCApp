//
//  Constants.swift
//  OrzMC
//
//  Created by joker on 5/1/24.
//

import Foundation

struct Constants {

    static let sidebarWidth: CGFloat = 320

    static let minWidth: CGFloat = 3 * sidebarWidth

    static let minHeight: CGFloat = minWidth * 0.618
    
    static let feedbackEmail = "824219521@qq.com"

    /// Minecraft Usage Guidelines 要求的官方免责声明。
    static let disclaimer = "NOT AN OFFICIAL MINECRAFT PRODUCT. NOT APPROVED BY OR ASSOCIATED WITH MOJANG OR MICROSOFT."
    
    /// https://docs.papermc.io/paper/dev/debugging#using-a-remote-debugger
    static let defaultJVMDebuggerArgs = "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
}
