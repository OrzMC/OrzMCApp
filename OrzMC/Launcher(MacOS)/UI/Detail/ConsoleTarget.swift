//
//  ConsoleTarget.swift
//  OrzMC
//

import Foundation

/// 控制台要打开的实例（`Identifiable` 供 `navigationDestination(item:)` / `openWindow(value:)` 用）。
///
/// `software == nil` 表示**客户端实例**（`版本#Client`）；否则是对应的服务端核心。
struct ConsoleTarget: Identifiable, Hashable, Codable {
    let versionId: String
    let software: SettingsModel.ServerSoftware?

    var id: String {
        "\(versionId)#\(software?.rawValue ?? "Client")"
    }

    var title: String {
        "\(versionId) \(software?.rawValue ?? "Client")"
    }
}
