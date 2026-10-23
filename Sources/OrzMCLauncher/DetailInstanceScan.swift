//
//  DetailInstanceScan.swift
//  OrzMCLauncher
//

import Foundation

/// 详情页「实例卡片」需要的一次性磁盘检查：**所有文件 IO 都集中在这里**，
/// 因而可以在后台线程跑，主线程只负责把结果写进 SwiftUI 状态。
///
/// 之前这段逻辑写在 `BasicInfo.refreshInstances()` 里、跑在主线程上，每 1.5s 一轮：
/// 2 个客户端 + 5 个核心 × 每条目录一次 `fileExists` ≈ 40 次同步 stat，
/// 加上客户端类型标记（再读 2~3 个路径）——窗口卡顿的直接来源之一。
/// 现在拆成「主线程造描述（纯内存） → 后台扫描（纯路径 + 注入的 IO） → 主线程赋值」。
public struct DetailInstanceScan: Sendable {

    /// 一个实例要检查什么。
    public struct Instance: Sendable, Equatable, Identifiable {
        public let id: String
        /// 客户端卡片才有：`Vanilla` / `Fabric`（服务端为 `nil`）。
        public let clientKind: String?
        /// 实例根目录（判定"卡片是否该显示"、读取客户端类型标记）。
        public let rootPath: String
        /// 需要 stat 的目录行路径。
        public let paths: [String]

        public init(id: String, clientKind: String?, rootPath: String, paths: [String]) {
            self.id = id
            self.clientKind = clientKind
            self.rootPath = rootPath
            self.paths = paths
        }
    }

    /// 扫描结果（两个字典都已按实例 id 索引，视图直接查表）。
    public struct Result: Sendable, Equatable {
        /// `实例 id → path → 是否存在`
        public let entryExists: [String: [String: Bool]]
        /// 客户端卡片：这一版**被启动过**的类型（含旧安装的兼容推断）。
        public let markedKinds: [String: Set<String>]

        public init(entryExists: [String: [String: Bool]] = [:], markedKinds: [String: Set<String>] = [:]) {
            self.entryExists = entryExists
            self.markedKinds = markedKinds
        }

        public static let empty = Result()
    }

    /// 可注入的文件系统动作（单测用假实现，生产用 `live()`）。
    public struct Environment: Sendable {
        public var exists: @Sendable (String) -> Bool
        public var markedKinds: @Sendable (String) -> Set<String>?
        public var legacyKinds: @Sendable (String, String) -> Set<String>

        public init(
            exists: @escaping @Sendable (String) -> Bool,
            markedKinds: @escaping @Sendable (String) -> Set<String>?,
            legacyKinds: @escaping @Sendable (String, String) -> Set<String>
        ) {
            self.exists = exists
            self.markedKinds = markedKinds
            self.legacyKinds = legacyKinds
        }

        public static func live() -> Environment {
            Environment(
                exists: { FileManager.default.fileExists(atPath: $0) },
                markedKinds: { ClientKindMarkers.markedKinds(clientDir: $0) },
                legacyKinds: { dir, version in
                    ClientKindMarkers.legacyKinds(clientDir: dir, version: version)
                }
            )
        }
    }

    private let environment: Environment

    public init(environment: Environment = .live()) {
        self.environment = environment
    }

    /// 在后台线程跑一次扫描（视图层直接 `await` 这个，不用自己拼 `Task.detached`）。
    ///
    /// 放在这里而不是视图里：`Task.detached` 的闭包是 `sending`，
    /// 在 `@MainActor` 里直接捕获一堆局部值会被并发检查拦下来；
    /// 这个方法是 `nonisolated`，捕获的都是 `Sendable` 值类型，编译期就干净。
    public func scanInBackground(_ instances: [Instance], version: String) async -> Result {
        await Task.detached(priority: .utility) { [self] in
            scan(instances, version: version)
        }.value
    }

    /// 扫一批实例。**纯函数**：同样的输入（+ 同样的磁盘）总是同样的结果，可安全地在后台调用。
    ///
    /// - Parameter version: 当前版本 id（旧安装推断需要它拼 `versions/<id>.jar`）。
    public func scan(_ instances: [Instance], version: String) -> Result {
        var exists: [String: [String: Bool]] = [:]
        var kinds: [String: Set<String>] = [:]
        exists.reserveCapacity(instances.count)
        kinds.reserveCapacity(instances.count)

        for instance in instances {
            var rows: [String: Bool] = [:]
            rows.reserveCapacity(instance.paths.count)
            for path in instance.paths {
                rows[path] = environment.exists(path)
            }
            exists[instance.id] = rows

            guard instance.clientKind != nil else { continue }
            // 标记优先；没有标记（旧安装）才做兼容推断——但只有目录真的存在才值得推断，
            // 否则每个不存在的客户端卡都会白读 2 个路径。
            guard rows[instance.rootPath] ?? environment.exists(instance.rootPath) else { continue }
            let marked = environment.markedKinds(instance.rootPath)
                ?? environment.legacyKinds(instance.rootPath, version)
            kinds[instance.id] = marked
        }
        return Result(entryExists: exists, markedKinds: kinds)
    }
}
