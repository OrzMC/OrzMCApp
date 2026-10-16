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

    /// https://docs.papermc.io/paper/dev/debugging#using-a-remote-debugger
    static let defaultJVMDebuggerArgs = "-agentlib:jdwp=transport=dt_socket,server=y,suspend=n,address=*:5005"
}
