import Foundation
import Game
import HangarAPI
import JokerKits
import Observation
import OrzMCLauncher

/// 插件管理：**已装插件（本地扫描）+ Hangar 目录** → 安装 / 更新。
///
/// 关键规则（对齐 Paper 官方更新机制，不是我们自创）：
/// - **没装过** → 下载进 `plugins/`，下次启动即加载；
/// - **已经装了**（无论版本新旧）→ 下载进 `plugins/update/`，服务端**下次启动时**自动替换旧 jar，
///   运行中的服务端不会因为磁盘上多了个 jar 就加载它。
///
/// 状态分两层：
/// - 本地状态（扫描 `plugins/` 得到）**立刻**可得，列表先渲染它；
/// - 远端最新版本要联网，点了「Check Updates」才去查（15 个项目 = 15 次请求，不该每次开面板都跑）。
@MainActor
@Observable
final class PluginManagerModel {

    /// 列表一行：Hangar 目录项，或"只在本地、目录里没有"的 jar。
    struct Row: Identifiable {
        enum Kind: Equatable {
            /// Hangar 目录里的项目（name 唯一）。
            case project
            /// 本地有、但目录里没匹配到（玩家自己放的 / 已下架的插件）。
            case localOnly
        }

        let id: String
        let name: String
        let summary: String?
        let kind: Kind
        /// 本地已装的版本（认不出 → 文件名）。
        let installedVersion: String?
        /// 远端最新版本（只在「Check Updates」后才有）。
        var latestVersion: String?

        var isInstalled: Bool { installedVersion != nil }

        /// 有更新（本地有 + 已知远端最新 + 版本不同）。
        var updateAvailable: Bool {
            guard let installedVersion, let latestVersion else { return false }
            return PluginInstaller.normalize(installedVersion) != PluginInstaller.normalize(latestVersion)
        }
    }

    private(set) var rows: [Row] = []
    private(set) var installedJars: [InstalledPlugin] = []
    /// 正在拉 Hangar 目录。
    private(set) var isLoadingCatalog = false
    /// 正在查最新版本（"Check Updates"）。
    private(set) var isCheckingUpdates = false
    /// 正在下载的项目名（同一时刻只允许一个，避免并发写同一目录）。
    private(set) var busyPlugin: String?
    /// 最近一次操作结果（"已安装到 plugins/update/" 之类），UI 提示用。
    private(set) var lastMessage: String?

    var error: LauncherError?
    var searchText = ""

    /// 当前实例的目录（启动面板时绑定）。
    private(set) var versionId: String?
    private var pluginsDir = ""
    private var updateDir = ""

    private var projects: [PluginProject] = []

    // MARK: 绑定 / 刷新

    /// 绑定到某个服务端实例（`版本` + 游戏根目录），并立刻扫一遍本地。
    func bind(versionId: String, rootDir: String) {
        self.versionId = versionId
        pluginsDir = GamePlan.serverPluginDir(version: versionId, type: .paper, root: rootDir)
        updateDir = GamePlan.serverPluginUpdateDir(version: versionId, type: .paper, root: rootDir)
        refreshLocal()
    }

    /// 重新扫描 `plugins/`（目录可能被 Finder/服务端自己改过）。
    func refreshLocal() {
        installedJars = PluginInstaller.scan(pluginsDir: pluginsDir)
        rebuildRows()
    }

    var filteredRows: [Row] {
        let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !keyword.isEmpty else { return rows }
        return rows.filter {
            $0.name.lowercased().contains(keyword) || ($0.summary?.lowercased().contains(keyword) ?? false)
        }
    }

    var updateCount: Int { rows.filter(\.updateAvailable).count }

    /// 展示用路径（UI 里告诉用户"装到哪"）。
    var pluginsDirectory: String { pluginsDir }
    var updateDirectory: String { updateDir }

    /// 拉 Hangar 目录（联网，按需）。
    func loadCatalogIfNeeded() async {
        guard projects.isEmpty, !isLoadingCatalog else { return }
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            // `PaperPlugin` 不是 `Sendable`：每次调用现建一个局部值，别存成属性（否则跨隔离域发送会报错）。
            projects = try await PaperPlugin().allPlugin()
            rebuildRows()
        } catch {
            self.error = LauncherError.wrap(error, fallbackCode: "E_NETWORK")
        }
    }

    /// 查每个目录项的最新版本（"Check Updates"）。
    func checkUpdates() async {
        guard !projects.isEmpty, !isCheckingUpdates else { return }
        isCheckingUpdates = true
        defer { isCheckingUpdates = false }
        var latest: [String: String] = [:]
        for project in projects {
            guard let name = project.name else { continue }
            if let download = try? await PaperPlugin().latesetReleaseVersionDownload(of: project, version: nil),
               let fileName = download.fileInfo?.name,
               let version = PluginInstaller.versionToken(in: fileName) {
                latest[name] = version
            }
        }
        for index in rows.indices {
            rows[index].latestVersion = latest[rows[index].name]
        }
        if latest.isEmpty {
            lastMessage = "Could not reach Hangar for any plugin."
        }
    }

    // MARK: 安装 / 更新

    /// 安装或更新一行：**新装 → `plugins/`；已装 → `plugins/update/`**。
    func install(_ row: Row) async {
        guard busyPlugin == nil, let versionId else { return }
        guard let project = projects.first(where: { $0.name == row.name }) else {
            lastMessage = "\(row.name) is not in the Hangar catalog — install it manually."
            return
        }
        busyPlugin = row.name
        defer { busyPlugin = nil }
        do {
            guard let plan = try await PaperPlugin().installPlan(
                for: project,
                pluginsDir: pluginsDir,
                updateDir: updateDir
            ) else {
                lastMessage = "\(row.name): no downloadable release for this server."
                return
            }
            try await Downloader.download(plan.item)
            refreshLocal()
            lastMessage = Self.successMessage(for: plan)
            _ = versionId
        } catch {
            self.error = LauncherError.wrap(error, fallbackCode: "E_NETWORK")
        }
    }

    /// 更新全部「有更新」的行（一次一个，顺序执行）。
    func updateAll() async {
        let targets = rows.filter(\.updateAvailable)
        for row in targets where busyPlugin == nil {
            await install(row)
        }
    }

    /// 结果文案：讲清"装到哪、什么时候生效"——这是用户最容易搞错的地方。
    static func successMessage(for plan: PluginInstallPlan) -> String {
        switch plan.target {
        case .plugins:
            return "\(plan.project): installed to plugins/ — loaded on next start."
        case .update:
            return "\(plan.project): update queued in plugins/update/ — applied on next restart."
        }
    }

    // MARK: 行构建

    private func rebuildRows() {
        var result: [Row] = []
        var matchedNames: Set<String> = []

        for project in projects {
            guard let name = project.name else { continue }
            let jars = installedJars.filter { PluginInstaller.belongs(jarNamed: $0.fileName, toProject: name) }
            if let jar = jars.first { matchedNames.insert(jar.fileName) }
            result.append(
                Row(
                    id: "project:\(name)",
                    name: name,
                    summary: project.description,
                    kind: .project,
                    installedVersion: jars.first.map { $0.version ?? $0.baseName },
                    latestVersion: nil
                )
            )
        }

        // 目录里没匹配到、但本地确实存在的 jar：也要显示（否则用户看不到自己手装的插件）。
        for jar in installedJars where !matchedNames.contains(jar.fileName) {
            result.append(
                Row(
                    id: "local:\(jar.fileName)",
                    name: jar.baseName,
                    summary: "Installed locally (not matched to a Hangar project)",
                    kind: .localOnly,
                    installedVersion: jar.version ?? jar.baseName,
                    latestVersion: nil
                )
            )
        }

        result.sort { lhs, rhs in
            if lhs.updateAvailable != rhs.updateAvailable { return lhs.updateAvailable }
            if lhs.isInstalled != rhs.isInstalled { return lhs.isInstalled }
            return lhs.name.lowercased() < rhs.name.lowercased()
        }
        rows = result
    }
}
