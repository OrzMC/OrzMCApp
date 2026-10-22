//
//  DetailInstance.swift
//  OrzMC
//

import Foundation

/// 详情页里「一个可查看的实例」：某个客户端类型（Vanilla/Fabric）或某个服务端核心（Paper/…）。
///
/// 一个版本最多 6 个实例：2 个客户端类型 + 4 个服务端核心。详情页把它们**按类型分组全部列出**，
/// 不再随工具栏的“当前类型”切换（工具栏的当前类型只决定主按钮启动谁）。
struct DetailInstance: Identifiable {
    let id: String
    /// 面板标题（`Client (Fabric)` / `Paper`）……
    /// 展示用的本地化标题在视图层拼（服务端用 `Server (%@)`，客户端用 `Client (%@)`）。
    let title: String
    /// `nil` = 客户端。
    let software: SettingsModel.ServerSoftware?
    /// 客户端类型（`software == nil` 时有效）。
    let clientKind: SettingsModel.ClientKind?

    var versionId: String {
        String(id.split(separator: "#").first ?? "")
    }

    var isClient: Bool { software == nil }

    /// 客户端实例（`Vanilla` / `Fabric`）。
    static func clients(versionId: String) -> [DetailInstance] {
        SettingsModel.ClientKind.allCases.map { kind in
            DetailInstance(
                id: "\(versionId)#client-\(kind.rawValue)",
                title: "Client (\(kind.rawValue))",
                software: nil,
                clientKind: kind
            )
        }
    }

    /// 服务端实例（每个核心一个：各自的目录、控制台、生命周期）。
    static func servers(versionId: String) -> [DetailInstance] {
        SettingsModel.ServerSoftware.allCases.map { software in
            DetailInstance(
                id: "\(versionId)#\(software.rawValue)",
                title: software.rawValue,
                software: software,
                clientKind: nil
            )
        }
    }
}
