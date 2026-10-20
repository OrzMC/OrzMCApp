//
//  GameCatalogService.swift
//  OrzMC
//
//  Created by Codex on 2026/5/23.
//

import Game
import MojangAPI

struct GameCatalogService {
    func fetchVersions(root: String = GamePlan.defaultRoot) async throws -> [Version] {
        await MojangCache.configure(root: root)
        return try await Mojang.manifest().versions
    }

    func fetchGameInfo(for version: Version, root: String = GamePlan.defaultRoot) async throws -> GameVersion? {
        await MojangCache.configure(root: root)
        return try await version.gameVersion
    }
}
