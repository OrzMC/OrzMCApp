import Foundation

/// 记录「某个版本下、某种客户端类型**被启动过**」。
///
/// 为什么需要它：Vanilla 与 Fabric 共用同一个 `<version>/client` 目录，
/// 只看目录是否存在的话，启动其中一种会让**两张卡片同时出现**（用户实测反馈）。
/// 因此每次启动客户端就在客户端目录里落一个标记文件，详情页按标记决定显示哪张卡。
///
/// 标记位置：`<client>/.orzmc/client-kinds/<Kind>`（空文件；与游戏文件放一起，
/// 换机器/重置 UserDefaults 也不会丢）。
public enum ClientKindMarkers {

    public static let directoryName = ".orzmc/client-kinds"

    /// 打标记（幂等）。失败不抛错：标记只是界面提示，不该挡住启动。
    public static func mark(clientDir: String, kind: String) {
        let dir = (clientDir as NSString).appendingPathComponent(directoryName)
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: (dir as NSString).appendingPathComponent(kind),
            contents: Data()
        )
    }

    /// 读取已标记的类型；`nil` = 还没有任何标记（旧安装，交给调用方做兼容推断）。
    public static func markedKinds(clientDir: String) -> Set<String>? {
        let dir = (clientDir as NSString).appendingPathComponent(directoryName)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: dir), !entries.isEmpty else {
            return nil
        }
        return Set(entries.filter { !$0.hasPrefix(".") })
    }

    /// 旧安装（没有标记）时的兼容推断：
    /// - 有 `libraries/net/fabricmc/fabric-loader` → 认为装过 Fabric；
    /// - 客户端 jar `versions/<version>.jar` 存在 → 认为装过 Vanilla；
    /// - 都没有但目录非空 → 按 Vanilla 处理（历史上客户端默认就是 Vanilla）。
    public static func legacyKinds(clientDir: String, version: String) -> Set<String> {
        var kinds = Set<String>()
        let fabric = (clientDir as NSString)
            .appendingPathComponent("libraries/net/fabricmc/fabric-loader")
        if FileManager.default.fileExists(atPath: fabric) { kinds.insert("Fabric") }
        let jar = (clientDir as NSString)
            .appendingPathComponent("versions/\(version).jar")
        if FileManager.default.fileExists(atPath: jar) { kinds.insert("Vanilla") }
        if kinds.isEmpty { kinds.insert("Vanilla") }
        return kinds
    }
}
