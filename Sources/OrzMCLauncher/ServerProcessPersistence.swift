import Foundation
import OrzMCFoundation
#if canImport(Darwin)
import Darwin
#endif

/// 进程存活探测（`kill(pid, 0)`：系统调用，零成本、不起子进程）。
///
/// 之前 GUI 每秒跑一次 `ps` 全机扫描再字符串解析 —— 既耗 CPU，又会把**别人**的
/// `java ... nogui` 进程当成"我管理的服务端"，`Stop All` 于是误杀别人的机器。
/// 现在只探**自己登记过的** PID。
public protocol ProcessLivenessProbing: Sendable {
    func isAlive(_ processId: ProcessIdentifier) -> Bool
}

public struct KernelProcessLivenessProbe: ProcessLivenessProbing {
    public init() {}

    public func isAlive(_ processId: ProcessIdentifier) -> Bool {
        guard let pid = Int32(processId.rawValue), pid > 0 else { return false }
        #if canImport(Darwin)
        if kill(pid_t(pid), 0) == 0 { return true }
        // EPERM = 进程在、但不属于我 —— 对本用途仍算"活着"。
        return errno == EPERM
        #else
        return false
        #endif
    }
}

/// 进程登记的**持久化**（GUI 自己启动过哪些服务端）。
///
/// 存盘的意义：app 重启后仍能列出/停止上次启动的服务端，而不是"失忆"后
/// 靠全机 `ps` 乱猜。
public protocol ServerProcessPersisting: Sendable {
    /// 读回 `key → pid`（读失败一律当空，不得抛）。
    func load() -> [String: String]
    /// 整表覆盖写；实现必须原子（临时文件 + rename）。
    func save(_ records: [String: String])
}

/// 落盘实现：默认 `~/Library/Application Support/OrzMC/servers.json`。
///
/// 这是 **GUI 自己的簿记**，不是产品级共享契约（`install.conf` / `auth.json` 才是），
/// 所以放在 Application Support 而不是规范里的 `stateDir`。
public struct FileServerProcessPersistence: ServerProcessPersisting {
    public let path: String

    public init(path: String = FileServerProcessPersistence.defaultPath()) {
        self.path = path
    }

    public static func defaultPath(
        home: String = NSHomeDirectory(),
        isMacOS: Bool = true
    ) -> String {
        if isMacOS {
            return home + "/Library/Application Support/OrzMC/servers.json"
        }
        return home + "/.local/state/orzmc/gui-servers.json"
    }

    public func load() -> [String: String] {
        guard let data = FileManager.default.contents(atPath: path),
              let decoded = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }
        return decoded
    }

    public func save(_ records: [String: String]) {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(records) else { return }
        // 原子写：先写临时文件再 rename，避免断电/崩溃留下半截 JSON。
        let temporary = path + ".tmp"
        guard (try? data.write(to: URL(fileURLWithPath: temporary))) != nil else { return }
        _ = try? FileManager.default.replaceItemAt(
            URL(fileURLWithPath: path), withItemAt: URL(fileURLWithPath: temporary))
    }
}

/// 内存实现（单测用）。
public final class InMemoryServerProcessPersistence: ServerProcessPersisting, @unchecked Sendable {
    private var records: [String: String]
    private let lock = NSLock()

    public init(records: [String: String] = [:]) {
        self.records = records
    }

    public func load() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        return records
    }

    public func save(_ records: [String: String]) {
        lock.lock()
        defer { lock.unlock() }
        self.records = records
    }
}
