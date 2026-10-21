import Testing
@testable import OrzMCLauncher

@Suite struct GameDirectoryCatalogTests {

    private func server(_ software: String) -> [GameDirectoryEntry] {
        GameDirectoryCatalog.serverEntries(
            softwareId: software,
            serverDir: "/r/server/\(software)",
            worldDir: "/r/server/\(software)/world",
            logsDir: "/r/server/\(software)/logs",
            pluginsDir: "/r/server/\(software)/plugins",
            pluginUpdatesDir: "/r/server/\(software)/plugins/update",
            modsDir: "/r/server/\(software)/mods",
            configDir: "/r/server/\(software)/config"
        )
    }

    @Test func everyServerHasRootWorldLogs() {
        for software in ["paper", "vanilla", "fabric", "forge"] {
            let kinds = server(software).map(\.kind)
            #expect(kinds.contains(.root), "\(software)")
            #expect(kinds.contains(.world), "\(software)")
            #expect(kinds.contains(.logs), "\(software)")
        }
    }

    @Test func paperHasPluginsAndUpdateQueue() {
        let kinds = server("paper").map(\.kind)
        #expect(kinds.contains(.plugins))
        #expect(kinds.contains(.pluginUpdates))
        #expect(!kinds.contains(.mods), "Paper 用插件，不该显示 mods")
        let paths = server("paper").map(\.path)
        #expect(paths.contains("/r/server/paper/plugins/update"))
    }

    @Test func fabricAndForgeHaveModsAndConfigs() {
        for software in ["fabric", "forge"] {
            let kinds = server(software).map(\.kind)
            #expect(kinds.contains(.mods), "\(software)")
            #expect(kinds.contains(.config), "\(software)")
            #expect(!kinds.contains(.plugins), "\(software)")
        }
    }

    @Test func vanillaOnlyHasCommonDirectories() {
        #expect(server("vanilla").map(\.kind) == [.root, .world, .logs])
    }

    @Test func onlyRootShowsWhenMissing() {
        for software in ["paper", "vanilla", "fabric", "forge"] {
            for entry in server(software) {
                #expect(entry.showsWhenMissing == (entry.kind == .root), "\(software) \(entry.kind)")
            }
        }
    }

    @Test func everyEntryHasNonEmptyDetail() {
        for software in ["paper", "vanilla", "fabric", "forge"] {
            for entry in server(software) {
                #expect(!entry.title.isEmpty)
                #expect(!entry.detail.isEmpty, "\(entry.kind) 必须有一句说明")
            }
        }
    }

    @Test func clientEntriesFollowClientType() {
        let vanilla = GameDirectoryCatalog.clientEntries(
            clientType: "vanilla",
            clientDir: "/r/client",
            logsDir: "/r/client/logs",
            savesDir: "/r/client/saves",
            modsDir: "/r/client/mods",
            resourcePacksDir: "/r/client/resourcepacks"
        )
        #expect(!vanilla.map(\.kind).contains(.mods))

        let fabric = GameDirectoryCatalog.clientEntries(
            clientType: "fabric",
            clientDir: "/r/client",
            logsDir: "/r/client/logs",
            savesDir: "/r/client/saves",
            modsDir: "/r/client/mods",
            resourcePacksDir: "/r/client/resourcepacks"
        )
        #expect(fabric.map(\.kind).contains(.mods), "Fabric 客户端有 mods")
        #expect(fabric.map(\.kind).contains(.saves))
    }
}
