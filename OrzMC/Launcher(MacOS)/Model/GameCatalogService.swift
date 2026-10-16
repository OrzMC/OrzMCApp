//
//  GameCatalogService.swift
//  OrzMC
//
//  Created by Codex on 2026/5/23.
//

import Game
import MojangAPI

struct GameCatalogService {
    func fetchVersions() async throws -> [Version] {
        await MojangCache.configure(root: GamePlan.defaultRoot)
        return try await Mojang.manifest().versions
    }

    func fetchGameInfo(for version: Version) async throws -> GameVersion? {
        await MojangCache.configure(root: GamePlan.defaultRoot)
        return try await version.gameVersion
    }
}
