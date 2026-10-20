//
//  Version+MinecraftVersionSummary.swift
//  OrzMC
//

import MojangAPI
import OrzMCLauncher

/// 把 `MojangAPI.Version` 接到平台无关的 `VersionListFilter` 上
/// （过滤规则只有一份，写在 `Sources/OrzMCLauncher`，有单测）。
extension Version: @retroactive MinecraftVersionSummary {
    public var minecraftVersionId: String { id }

    public var minecraftVersionKind: MinecraftVersionKind {
        switch buildType {
        case .release: return .release
        case .snapshot: return .snapshot
        case .oldBeta: return .oldBeta
        case .oldAlpha: return .oldAlpha
        }
    }
}
