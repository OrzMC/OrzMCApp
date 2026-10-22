//
//  GameCatalogService.swift
//  OrzMC
//
//  Created by Codex on 2026/5/23.
//

import Game
import MojangAPI

struct GameCatalogService {
    /// 一次拿到「版本列表 + 最新正式版/快照标记」：清单里本来就有 `latest`，以前被丢掉了。
    func fetchSnapshot(root: String = GamePlan.defaultRoot) async throws -> VersionCatalogSnapshot {
        await MojangCache.configure(root: root)
        let manifest = try await Mojang.manifest()
        return VersionCatalogSnapshot(
            versions: manifest.versions,
            latestReleaseId: manifest.latest.release,
            latestSnapshotId: manifest.latest.snapshot
        )
    }

    func fetchGameInfo(for version: Version, root: String = GamePlan.defaultRoot) async throws -> GameVersion? {
        await MojangCache.configure(root: root)
        return try await version.gameVersion
    }
}
