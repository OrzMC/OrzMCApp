import Foundation

/// 某个版本**在磁盘上装了什么**（客户端 / 哪些服务端核心）。
///
/// 以前这段判断写在 `GameList` 的视图 body 里：每行 3 次 `FileManager` 存在性检查，
/// 每次重绘都跑一遍（列表滚动时就是几百次同步 stat）。现在抽成纯函数，
/// 由模型在**版本列表变化时算一次**并缓存，视图只管显示。
public struct VersionInstallState: Equatable, Sendable {
    /// 是否装了客户端。
    public var hasClient: Bool
    /// 已装的服务端核心标识（`paper` / `vanilla` / `fabric` / `forge`，按传入顺序）。
    public var servers: [String]

    public init(hasClient: Bool = false, servers: [String] = []) {
        self.hasClient = hasClient
        self.servers = servers
    }

    public static let none = VersionInstallState()

    public var hasServer: Bool { !servers.isEmpty }

    /// 某个服务端核心是否已装（`servers` 里存的是小写标识，如 `paper`）。
    ///
    /// 视图用这个替代直接 `stat` 目录：安装状态已由扫描器算好并缓存。
    public func hasServer(id: String) -> Bool {
        servers.contains { $0.caseInsensitiveCompare(id) == .orderedSame }
    }

    public var isEmpty: Bool { !hasClient && servers.isEmpty }

    /// 列表行里的标签（"Client" / "Paper server" …）。
    public var labels: [String] {
        var result = [String]()
        if hasClient { result.append("Client") }
        for server in servers { result.append("\(server.capitalized) server") }
        return result
    }

    /// 列表行里的**紧凑徽标**（`Client` / `Paper` / `Fabric`…）：比 "Paper server" 好扫。
    public var badges: [String] {
        var result = [String]()
        if hasClient { result.append("Client") }
        for server in servers { result.append(server.capitalized) }
        return result
    }

    /// 行首图标（SF Symbol）。
    public var symbolName: String {
        if hasClient { return "macbook" }
        if hasServer { return "xserve" }
        return "cube"
    }
}

/// 扫目录判断安装状态（`exists` 可注入，便于单测）。
public struct InstalledVersionScanner: Sendable {
    public typealias Exists = @Sendable (String) -> Bool

    private let exists: Exists

    public init(exists: @escaping Exists) {
        self.exists = exists
    }

    /// 生产用实现（真实文件系统）。
    public static func live() -> InstalledVersionScanner {
        InstalledVersionScanner { path in
            FileManager.default.fileExists(atPath: path)
        }
    }

    /// - Parameters:
    ///   - serverDirs: `(核心标识, 目录路径)`；只传**已存在**时算作已装。
    public func state(
        clientDir: String?,
        serverDirs: [(id: String, path: String)]
    ) -> VersionInstallState {
        VersionInstallState(
            hasClient: clientDir.map(exists) ?? false,
            servers: serverDirs.filter { exists($0.path) }.map(\.id)
        )
    }
}
