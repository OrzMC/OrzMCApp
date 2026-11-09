//
//  PluginSheetTarget.swift
//  OrzMC
//

import Foundation

/// 插件管理面板的目标（`Identifiable` 供 `sheet(item:)` 用）。
struct PluginSheetTarget: Identifiable {
    let versionId: String
    var id: String { versionId }
}

/// 实例卡片上的「附加内容」面板入口：插件（Paper）与模组（Fabric/Forge）。
///
/// **合并成一个枚举**：同一条视图链上只能挂一个 `.sheet`（2026-11-05 MCSM 踩过：
/// 挂两个时后挂的永远不弹），所以插件与模组共用这一个 item。
enum InstanceAddonSheet: Identifiable {
    case plugins(PluginSheetTarget)
    case mods(ModsSheetTarget)

    var id: String {
        switch self {
        case .plugins(let target): return "plugins-\(target.id)"
        case .mods(let target): return "mods-\(target.id)"
        }
    }
}
