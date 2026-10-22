//
//  Version+.swift
//  OrzMC
//
//  Created by joker on 2024/4/28.
//

import SwiftUI
import MojangAPI

extension Version {
    /// 版本类型的展示名（`buildType.rawValue` 是 API 值，不能直接当 UI 文案）。
    var localizedBuildTypeTitle: String {
        switch buildType {
        case .release: return String(localized: "Release")
        case .snapshot: return String(localized: "Snapshot")
        case .oldAlpha: return String(localized: "Old Alpha")
        case .oldBeta: return String(localized: "Old Beta")
        }
    }

    var typeTagColor: Color {
        switch buildType {
        case .release:
            return .accentColor
        case .snapshot:
            return .mint
        case .oldAlpha:
            return .red
        case .oldBeta:
            return .orange
        }
    }
}
