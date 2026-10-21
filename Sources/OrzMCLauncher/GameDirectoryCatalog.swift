import Foundation

/// 详情页里的一条「常用目录」。
///
/// 为什么要有「标题 + 说明」而不是直接把路径摆出来：路径又长又重复（前缀人人一样），
/// 用户真正需要的是「这是干什么的、里面放什么」，路径只在悬停提示和"在 Finder 中打开"时需要。
public struct GameDirectoryEntry: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        /// 实例根目录（`server.properties` / `eula.txt` / 日志外的全部配置）。
        case root
        /// 世界存档（`<level-name>`）。
        case world
        /// 日志（`logs/latest.log`）。
        case logs
        /// 插件目录（Paper/Spigot 系）。
        case plugins
        /// 插件更新目录（Paper 的 `update-folder`，下次重启应用）。
        case pluginUpdates
        /// mod 目录（Fabric/Forge）。
        case mods
        /// mod 配置目录（Fabric/Forge）。
        case config
        /// 客户端存档。
        case saves
        /// 客户端资源包。
        case resourcePacks
    }

    public let kind: Kind
    public let title: String
    /// 一句话讲清"里面放什么 / 什么时候生效"。
    public let detail: String
    public let path: String
    /// 是否**允许**在不存在时也显示（默认只在存在时显示；根目录始终显示）。
    public let showsWhenMissing: Bool

    public var id: String { "\(kind.rawValue)|\(path)" }

    public init(
        kind: Kind,
        title: String,
        detail: String,
        path: String,
        showsWhenMissing: Bool = false
    ) {
        self.kind = kind
        self.title = title
        self.detail = detail
        self.path = path
        self.showsWhenMissing = showsWhenMissing
    }
}

/// 按「核心 / 客户端类型」决定显示哪些常用目录（纯逻辑，单测覆盖）。
public enum GameDirectoryCatalog {

    /// 服务端实例的常用目录。
    ///
    /// - 所有核心：根目录、世界存档、日志；
    /// - Paper：再加 `plugins/` 与 `plugins/update/`（插件 + 更新队列）；
    /// - Fabric / Forge：再加 `mods/` 与 `config/`；
    /// - Vanilla：没有插件/mod 目录（它也没有对应机制）。
    public static func serverEntries(
        softwareId: String,
        serverDir: String,
        worldDir: String,
        logsDir: String,
        pluginsDir: String,
        pluginUpdatesDir: String,
        modsDir: String,
        configDir: String
    ) -> [GameDirectoryEntry] {
        var entries: [GameDirectoryEntry] = [
            GameDirectoryEntry(
                kind: .root,
                title: "Server Folder",
                detail: "server.properties, eula.txt, banned lists and everything else the server writes.",
                path: serverDir,
                showsWhenMissing: true
            ),
            GameDirectoryEntry(
                kind: .world,
                title: "World",
                detail: "Level data (`level-name` in server.properties). Back this up before big changes.",
                path: worldDir
            ),
            GameDirectoryEntry(
                kind: .logs,
                title: "Logs",
                detail: "`logs/latest.log` — what the server console shows, including crashes.",
                path: logsDir
            ),
        ]

        switch softwareId.lowercased() {
        case "paper":
            entries.append(
                GameDirectoryEntry(
                    kind: .plugins,
                    title: "Plugins",
                    detail: "Drop plugin jars here — they load on the next start.",
                    path: pluginsDir
                )
            )
            entries.append(
                GameDirectoryEntry(
                    kind: .pluginUpdates,
                    title: "Plugin Updates",
                    detail: "Queued plugin updates — the server applies them on the next restart.",
                    path: pluginUpdatesDir
                )
            )
        case "fabric", "forge":
            entries.append(
                GameDirectoryEntry(
                    kind: .mods,
                    title: "Mods",
                    detail: "Mod jars — they load on the next start.",
                    path: modsDir
                )
            )
            entries.append(
                GameDirectoryEntry(
                    kind: .config,
                    title: "Mod Configs",
                    detail: "Per-mod config files written on first run.",
                    path: configDir
                )
            )
        default:
            break
        }
        return entries
    }

    /// 客户端实例的常用目录（`clientType` 传 `fabric` 时多一个 `mods/`）。
    public static func clientEntries(
        clientType: String,
        clientDir: String,
        logsDir: String,
        savesDir: String,
        modsDir: String,
        resourcePacksDir: String
    ) -> [GameDirectoryEntry] {
        var entries: [GameDirectoryEntry] = [
            GameDirectoryEntry(
                kind: .root,
                title: "Game Folder",
                detail: "options.txt, screenshots and everything else the client writes.",
                path: clientDir,
                showsWhenMissing: true
            ),
            GameDirectoryEntry(
                kind: .logs,
                title: "Logs",
                detail: "`logs/latest.log` — useful when the game crashes on launch.",
                path: logsDir
            ),
            GameDirectoryEntry(
                kind: .saves,
                title: "Saves",
                detail: "Single-player worlds.",
                path: savesDir
            ),
        ]
        if clientType.lowercased() == "fabric" {
            entries.append(
                GameDirectoryEntry(
                    kind: .mods,
                    title: "Mods",
                    detail: "Fabric mod jars — loaded on the next launch.",
                    path: modsDir
                )
            )
        }
        entries.append(
            GameDirectoryEntry(
                kind: .resourcePacks,
                title: "Resource Packs",
                detail: "Texture and resource packs available in-game.",
                path: resourcePacksDir
            )
        )
        return entries
    }
}
