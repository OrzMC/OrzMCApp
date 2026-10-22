//
//  VersionCatalogModel.swift
//  OrzMC
//

import Foundation
import Game
import MojangAPI
import Observation
import OrzMCLauncher

/// 一次清单拉取的结果：版本列表 + 「最新」标记（都在同一份 manifest 里）。
struct VersionCatalogSnapshot: Sendable {
    let versions: [Version]
    let latestReleaseId: String?
    let latestSnapshotId: String?
}

/// 版本目录：拉列表、过滤、选中、装了什么。
///
/// 只做"版本目录"这一件事（以前混在 390 行的 `GameModel` 里）。
/// - `filtered` 是**计算属性**：不再把派生结果复制成 `@State` 再两处同步；
/// - `installStates` 在列表/磁盘变化时算一次并缓存，视图 body 里不再做文件 IO；
/// - 选中变化通过 `onSelectionChange` 回调通知根模型（拉 gameInfo、刷 JRE），模型之间不互相持有。
@MainActor
@Observable
final class VersionCatalogModel {

    /// 注入点：默认走真实网络（`GameCatalogService`），单测可替换。
    typealias VersionsLoader = @Sendable (String) async throws -> VersionCatalogSnapshot
    typealias GameInfoLoader = @Sendable (Version, String) async throws -> GameVersion?

    private(set) var versions: [Version] = []
    private(set) var isLoading = false
    private(set) var gameInfoMap: [Version: GameVersion] = [:]
    private(set) var installStates: [String: VersionInstallState] = [:]
    /// 清单里的「最新正式版 / 最新快照」id（列表行显示「最新」徽标）。
    private(set) var latestReleaseId: String?
    private(set) var latestSnapshotId: String?
    /// 键盘上下键切换版本：`by = ±1` 走一格；`jumpToEdge` 时直接跳首/末（⌘↑ / ⌘↓）。
    /// 判定逻辑在 `VersionSelectionStepper`（纯函数，有单测）。
    func stepSelection(by delta: Int, jumpToEdge: Bool = false) {
        selected = VersionSelectionStepper.next(
            current: selected,
            list: filtered,
            delta: delta,
            jumpToEdge: jumpToEdge
        )
    }

    /// 上次成功拉清单的时间（侧边栏底部显示；跨启动保留）。
    private(set) var lastRefreshedAt: Date?

    var searchText = ""
    var releaseOnly = true

    var selected: Version? {
        didSet {
            guard selected != oldValue else { return }
            if let selected {
                onSelectionChange?(selected)
                loadGameInfoIfNeeded(for: selected)
                lastSelectedVersionId = selected.id
            }
        }
    }

    /// 上次选中的版本 id（由根模型从设置注入/保存）。
    var lastSelectedVersionId: String?

    /// 游戏根目录（多实例 = 换根）。变化时重算"装了什么"。
    var rootDir: String = GamePlan.defaultRoot {
        didSet {
            guard rootDir != oldValue else { return }
            refreshInstallStates()
        }
    }

    var onSelectionChange: ((Version) -> Void)?

    private let loadVersionsHandler: VersionsLoader
    private let loadGameInfoHandler: GameInfoLoader
    private let filter = VersionListFilter()
    private let scanner: InstalledVersionScanner

    init(
        scanner: InstalledVersionScanner = .live(),
        loadVersions: @escaping VersionsLoader = { root in
            try await GameCatalogService().fetchSnapshot(root: root)
        },
        loadGameInfo: @escaping GameInfoLoader = { version, root in
            try await GameCatalogService().fetchGameInfo(for: version, root: root)
        }
    ) {
        self.scanner = scanner
        self.loadVersionsHandler = loadVersions
        self.loadGameInfoHandler = loadGameInfo
        self.lastRefreshedAt = UserDefaults.standard.object(forKey: Self.lastRefreshedKey) as? Date
    }

    private static let lastRefreshedKey = "orzmc.catalog.lastRefreshedAt"

    // MARK: 派生

    /// 过滤后的列表（搜索 + 只看正式版）。
    var filtered: [Version] {
        filter.filter(versions: versions, searchText: searchText, releaseOnly: releaseOnly)
    }

    func gameInfo(for version: Version) -> GameVersion? { gameInfoMap[version] }

    func installState(for version: Version) -> VersionInstallState {
        installStates[version.id] ?? .none
    }

    /// 所需 Java major（来自 gameInfo）；未知时 `nil`。
    func requiredJavaMajor(for version: Version?) -> Int? {
        guard let version, let info = gameInfoMap[version], let java = info.javaVersion else {
            return nil
        }
        return Int(java.majorVersion)
    }

    // MARK: 加载

    func load() async throws {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let snapshot = try await loadVersionsHandler(rootDir)
        versions = snapshot.versions
        latestReleaseId = snapshot.latestReleaseId
        latestSnapshotId = snapshot.latestSnapshotId
        lastRefreshedAt = .now
        UserDefaults.standard.set(lastRefreshedAt, forKey: Self.lastRefreshedKey)
        refreshInstallStates()
        restoreSelection()
        if let selected { loadGameInfoIfNeeded(for: selected) }
    }

    /// 版本列表变化/删除文件后调用（列表滚动时不再逐行 stat）。
    func refreshInstallStates() {
        var states = [String: VersionInstallState]()
        for version in versions {
            states[version.id] = computedInstallState(for: version)
        }
        installStates = states
    }

    /// 只重算**一个版本**的“装了什么”。
    ///
    /// 详情页可见时每 1.5s 复核一次目录；以前每次都全量扫所有版本
    /// （几百个版本 × 5 个目录 = 数千次 stat / 1.5s）。列表徽标在加载、删除、
    /// 换根目录时已经全量刷新，详情页只需要关心当前选中的版本。
    func refreshInstallState(for version: Version) {
        installStates[version.id] = computedInstallState(for: version)
    }

    private func computedInstallState(for version: Version) -> VersionInstallState {
        scanner.state(
            clientDir: GamePlan.clientDir(version: version.id, root: rootDir),
            serverDirs: SettingsModel.ServerSoftware.allCases.map {
                (
                    $0.rawValue.lowercased(),
                    GamePlan.serverDir(version: version.id, type: $0.gameType, root: rootDir)
                )
            }
        )
    }

    /// 尽量复原上次选中的版本；没有就选过滤后的第一个。
    private func restoreSelection() {
        if let lastSelectedVersionId,
           let restored = versions.first(where: { $0.id == lastSelectedVersionId }) {
            selected = restored
            return
        }
        if selected == nil { selected = filtered.first }
    }

    /// 版本详情（gameInfo）是异步拉取的，**Java 需求依赖它**：到达后通知根模型同步一次。
    var onGameInfoLoaded: (() -> Void)?

    private func loadGameInfoIfNeeded(for version: Version) {
        guard gameInfoMap[version] == nil else { return }
        let handler = loadGameInfoHandler
        let root = rootDir
        Task { [weak self] in
            guard let info = try? await handler(version, root) else { return }
            self?.gameInfoMap[version] = info
            self?.onGameInfoLoaded?()
        }
    }
}
