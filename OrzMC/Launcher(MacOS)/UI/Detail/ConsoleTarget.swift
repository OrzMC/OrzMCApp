//
//  ConsoleTarget.swift
//  OrzMC
//

import Foundation

/// 控制台要打开的实例（`Identifiable` 供 `navigationDestination(item:)` / `openWindow(value:)` 用）。
///
/// 客户端按**类型**区分（`版本#Client-Vanilla` / `版本#Client-Fabric`）：两种客户端各有一个控制台，
/// 否则启动 Fabric 时 Vanilla 的入口也会亮起来、日志还会混在一起。
struct ConsoleTarget: Identifiable, Hashable, Codable {
    let versionId: String
    /// 服务端核心；`nil` = 客户端。
    let software: SettingsModel.ServerSoftware?
    /// 客户端类型（`software == nil` 时有效）。
    let clientKind: SettingsModel.ClientKind?

    init(versionId: String, software: SettingsModel.ServerSoftware) {
        self.versionId = versionId
        self.software = software
        self.clientKind = nil
    }

    init(versionId: String, clientKind: SettingsModel.ClientKind) {
        self.versionId = versionId
        self.software = nil
        self.clientKind = clientKind
    }

    var id: String {
        if let software {
            return "\(versionId)#\(software.rawValue)"
        }
        return "\(versionId)#Client-\(clientKind?.rawValue ?? "Vanilla")"
    }

    var title: String {
        if let software {
            return "\(versionId) \(software.rawValue)"
        }
        return "\(versionId) Client (\(clientKind?.rawValue ?? "Vanilla"))"
    }
}
