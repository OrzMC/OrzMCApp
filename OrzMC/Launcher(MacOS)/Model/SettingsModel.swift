//
//  SettingsModel.swift
//  OrzMC
//
//  Created by wangzhizhou on 2024/9/26.
//

import Foundation
import Game
import OrzMCLauncher

/// 用户设置（**持久化**：重启后保留）。
///
/// 之前这些值全在内存里，关掉 app 就回到默认；内存参数还是写死的 `512M/2G`，
/// 且客户端类型固定 vanilla（引擎 `ClientInfo.type` 用了默认值）。现在：
/// - 内存参数可配，**校验走引擎的 `MemorySpec`**（同一套规则，不另写一份正则）；
/// - 客户端类型可配（vanilla / fabric）；
/// - 全部存 `UserDefaults`，键名带 `orzmc.` 前缀避免撞车。
@Observable
final class SettingsModel {

    enum Keys {
        static let enableJVMDebugger = "orzmc.settings.enableJVMDebugger"
        static let jvmDebuggerArgs = "orzmc.settings.jvmDebuggerArgs"
        static let serverSoftware = "orzmc.settings.serverSoftware"
        static let clientType = "orzmc.settings.clientType"
        static let minMem = "orzmc.settings.minMem"
        static let maxMem = "orzmc.settings.maxMem"
        static let username = "orzmc.settings.username"
        static let lastSelectedVersion = "orzmc.settings.lastSelectedVersion"
        static let gameMode = "orzmc.settings.gameMode"
        static let rootDir = "orzmc.settings.rootDir"
    }

    static let defaultMinMem = "512M"
    static let defaultMaxMem = "2G"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.enableJVMDebugger = defaults.bool(forKey: Keys.enableJVMDebugger)
        self.jvmDebuggerArgs = defaults.string(forKey: Keys.jvmDebuggerArgs) ?? ""
        self.serverSoftware = SettingsModel.ServerSoftware(
            rawValue: defaults.string(forKey: Keys.serverSoftware) ?? ""
        ) ?? .paper
        self.clientType = ClientKind(
            rawValue: defaults.string(forKey: Keys.clientType) ?? ""
        ) ?? .vanilla
        self.minMem = defaults.string(forKey: Keys.minMem) ?? SettingsModel.defaultMinMem
        self.maxMem = defaults.string(forKey: Keys.maxMem) ?? SettingsModel.defaultMaxMem
        self.username = defaults.string(forKey: Keys.username) ?? ""
        self.lastSelectedVersionId = defaults.string(forKey: Keys.lastSelectedVersion)
        self.gameMode = GameMode(
            rawValue: defaults.string(forKey: Keys.gameMode) ?? ""
        ) ?? .client
        self.rootDir = defaults.string(forKey: Keys.rootDir) ?? GamePlan.defaultRoot
    }

    /// 远程 JVM 调试（服务端）。
    var enableJVMDebugger: Bool {
        didSet { defaults.set(enableJVMDebugger, forKey: Keys.enableJVMDebugger) }
    }

    var jvmDebuggerArgs: String {
        didSet { defaults.set(jvmDebuggerArgs, forKey: Keys.jvmDebuggerArgs) }
    }

    /// Server 端核心类型（Paper/Vanilla/Fabric/Forge）。目前为全局设置。
    var serverSoftware: ServerSoftware {
        didSet { defaults.set(serverSoftware.rawValue, forKey: Keys.serverSoftware) }
    }

    /// 客户端类型（引擎 `Game.GameType` 里客户端支持的部分）。
    var clientType: ClientKind {
        didSet { defaults.set(clientType.rawValue, forKey: Keys.clientType) }
    }

    var minMem: String {
        didSet { defaults.set(minMem, forKey: Keys.minMem) }
    }

    var maxMem: String {
        didSet { defaults.set(maxMem, forKey: Keys.maxMem) }
    }

    /// 离线用户名（下次启动预填）。
    var username: String {
        didSet { defaults.set(username, forKey: Keys.username) }
    }

    /// 上次选中的版本 id（版本目录加载后尽量复原）。
    var lastSelectedVersionId: String? {
        didSet { defaults.set(lastSelectedVersionId, forKey: Keys.lastSelectedVersion) }
    }

    /// 客户端 / 服务端（下次启动保留）。
    var gameMode: GameMode {
        didSet { defaults.set(gameMode.rawValue, forKey: Keys.gameMode) }
    }

    /// 游戏根目录（规范 §3 的全局 `--root-dir`；多实例就是换一个根）。
    ///
    /// 引擎的 `ClientInfo` / `ServerInfo` / `GamePlan.*(root:)` 都已参数化，
    /// GUI 之前固定用 `GamePlan.defaultRoot`，等于"多实例不可用"。
    var rootDir: String {
        didSet { defaults.set(rootDir, forKey: Keys.rootDir) }
    }

    var isRootDirValid: Bool { rootDir.hasPrefix("/") }

    func resetRootDir() {
        rootDir = GamePlan.defaultRoot
    }

    // MARK: 校验（共用引擎规则）

    /// 内存参数的非法项说明；`nil` = 合法。
    ///
    /// 直接复用引擎 `MemorySpec`（规范 `cli-surface.md` §5），不另写一份正则，
    /// 免得 CLI 说合法、GUI 说非法。
    var memoryValidationMessage: String? {
        MemorySpec.firstInvalid(min: minMem, max: maxMem)
    }

    var isMemoryValid: Bool { memoryValidationMessage == nil }
}

// MARK: - 枚举

extension SettingsModel {
    /// 服务端核心类型。
    enum ServerSoftware: String, CaseIterable, Identifiable {
        case paper = "Paper"
        case vanilla = "Vanilla"
        case fabric = "Fabric"
        case forge = "Forge"

        var id: String { rawValue }

        var gameType: GameType {
            switch self {
            case .paper: return .paper
            case .vanilla: return .vanilla
            case .fabric: return .fabric
            case .forge: return .forge
            }
        }

        /// 是否支持 Bukkit/Paper 插件目录（目前仅 Paper）。
        var supportsPlugins: Bool { self == .paper }
    }

    /// 客户端类型：引擎只支持 vanilla / fabric。
    enum ClientKind: String, CaseIterable, Identifiable {
        case vanilla = "Vanilla"
        case fabric = "Fabric"

        var id: String { rawValue }

        var gameType: GameType {
            switch self {
            case .vanilla: return .vanilla
            case .fabric: return .fabric
            }
        }
    }
}
