//
//  SelfHostedErrorText.swift
//  OrzMC
//

import Foundation
import OrzMCProtocol

/// 把自建服务器相关的网络/协议错误翻译成"一眼能懂"的一句话。
///
/// 放在应用层（而不是 `OrzMCProtocol`）：`Sources/*` 不做本地化（它同时也给 CLI 用），
/// 用户可见文案统一由应用侧 xcstrings 提供。
enum SelfHostedErrorText {

    /// - Parameter address: 已经拼好的 `host[:port]`。
    ///   **不要**把端口作为 `Int` 插值进字符串：会按地区加千位分隔符（实测 `25,565`）。
    static func describe(_ error: Error, address: String) -> String {
        switch error {
        case MCStreamError.connectFailed:
            return String(localized: "Can't connect to \(address). Check the address, the port and your network.")
        case MCStreamError.connectionClosed:
            return String(localized: "The server closed the connection. Check that the port belongs to Minecraft, not another service.")
        case MCSLPError.pingFailed, MCSLPError.packetMalFormat:
            return String(localized: "The server answered in an unexpected format. Is it a Minecraft server?")
        case MCRCONError.authFailed:
            return String(localized: "RCON password was rejected. Check the password in server.properties.")
        case MCRCONError.responseInvalid, MCRCONError.packetMalFormat:
            return String(localized: "RCON answered in an unexpected format.")
        case MCProbeError.timedOut:
            return String(localized: "The server didn't answer in time. Check the address and that the port is open.")
        case is MCStatusError:
            return String(localized: "This server returned status data this app doesn't understand.")
        default:
            return error.localizedDescription
        }
    }
}
