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
