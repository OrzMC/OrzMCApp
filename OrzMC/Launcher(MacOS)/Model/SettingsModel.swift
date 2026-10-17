//
//  SettingsModel.swift
//  OrzMC
//
//  Created by wangzhizhou on 2024/9/26.
//

import Foundation
import Game

@Observable
final class SettingsModel {
    
    var enableJVMDebugger: Bool = false
    
    var jvmDebuggerArgs: String = ""
    
    enum ServerSoftware: String, CaseIterable, Identifiable {
        case paper = "Paper"
        case vanilla = "Vanilla"
        case fabric = "Fabric"
        case forge = "Forge"

        var id: String { rawValue }

        var gameType: GameType {
            switch self {
            case .paper:
                return .paper
            case .vanilla:
                return .vanilla
            case .fabric:
                return .fabric
            case .forge:
                return .forge
            }
        }

        /// 是否支持 Bukkit/Paper 插件目录（目前仅 Paper）。
        var supportsPlugins: Bool { self == .paper }
    }

    /// Server 端核心类型（Paper/Vanilla/Fabric/Forge）。目前为全局设置。
    var serverSoftware: ServerSoftware = .paper
}
