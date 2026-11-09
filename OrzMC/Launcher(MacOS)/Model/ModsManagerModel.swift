//
//  ModsManagerModel.swift
//  OrzMC
//
//  「模组」面板的本地状态：只扫描 `mods/` 里已有的 jar。
//
//  2026-11-09：先给 Fabric / Forge 服务端一个**入口**（维护者要求模组按钮放在控制台左边）。
//  **搜索 / 安装 / 更新 / 卸载**（Modrinth、Hangar 渠道）下一轮再接入，所以这里没有目录、
//  没有下载、不改任何文件 —— 只回答"现在装了什么、目录在哪"。
//

import Foundation
import Game
import Observation
import OrzMCLauncher

@MainActor
@Observable
final class ModsManagerModel {

    struct Mod: Identifiable {
        let fileName: String
        /// 从文件名里认出来的版本号；认不出来就是 `nil`（不猜）。
        let version: String?

        var id: String { fileName }
    }

    private(set) var mods: [Mod] = []
    /// `mods/` 的绝对路径（"打开文件夹"与页面说明用）。
    private(set) var modsDirectory = ""
    var searchText = ""

    var filtered: [Mod] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return mods }
        return mods.filter { $0.fileName.lowercased().contains(keyword) }
    }

    /// 绑定到某个服务端实例：`版本 + 核心类型 + 游戏根目录` 决定 `mods/` 在哪。
    func bind(versionId: String, software: SettingsModel.ServerSoftware, rootDir: String) {
        modsDirectory = GamePlan.serverModsDir(
            version: versionId,
            type: software.gameType,
            root: rootDir
        )
        refresh()
    }

    func refresh() {
        guard !modsDirectory.isEmpty else { return }
        // `PluginInstaller.scan` 本身只是"扫一个目录里的 .jar"（忽略 `.jar.disabled`、不进子目录），
        // 与插件/模组无关；直接复用，避免再写一份同样的规则。
        mods = PluginInstaller.scan(pluginsDir: modsDirectory).map {
            Mod(fileName: $0.fileName, version: PluginInstaller.versionToken(in: $0.fileName))
        }
    }
}
