//
//  DetailInstance.swift
//  OrzMC
//

import Foundation

/// 详情页里「一个可查看的实例」（某个服务端核心，或客户端）。
struct DetailInstance: Identifiable {
    let id: String
    let title: String
    /// `nil` = 客户端。
    let software: SettingsModel.ServerSoftware?

    var versionId: String {
        String(id.split(separator: "#").first ?? "")
    }
}
