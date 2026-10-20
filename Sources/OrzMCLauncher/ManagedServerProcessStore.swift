import OrzMCFoundation

public struct ManagedServerProcessStore: Sendable {
    private var processes: [ManagedServerKey: ProcessIdentifier]
    private let registry: ServerProcessRegistry
    private let persistence: ServerProcessPersisting?

    /// - Parameters:
    ///   - processes: 初始集合；`nil` 时从 `persistence` 读回（app 重启后仍记得自己启动过哪些服务端）。
    ///   - persistence: 传 `nil` 表示纯内存（单测/预览）。
    public init(
        processes: [ManagedServerKey: ProcessIdentifier]? = nil,
        registry: ServerProcessRegistry = ServerProcessRegistry(),
        persistence: ServerProcessPersisting? = nil
    ) {
        self.registry = registry
        self.persistence = persistence
        if let processes {
            self.processes = processes
        } else if let persistence {
            self.processes = Self.decode(persistence.load())
        } else {
            self.processes = [:]
        }
    }

    private static func decode(_ records: [String: String]) -> [ManagedServerKey: ProcessIdentifier] {
        var result = [ManagedServerKey: ProcessIdentifier]()
        for (key, pid) in records {
            result[ManagedServerKey(rawValue: key)] = ProcessIdentifier(pid)
        }
        return result
    }

    private var encoded: [String: String] {
        var result = [String: String]()
        for (key, pid) in processes {
            result[key.rawValue] = pid.rawValue
        }
        return result
    }

    private func persist() {
        persistence?.save(encoded)
    }

    public var hasManagedRunningServers: Bool {
        registry.hasManagedRunningServers(processes)
    }

    public mutating func record(_ processId: ProcessIdentifier, for key: ManagedServerKey) {
        processes[key] = processId
        persist()
    }

    public func processId(for key: ManagedServerKey) -> ProcessIdentifier? {
        processes[key]
    }

    public func processIds() -> [ProcessIdentifier] {
        registry.processIds(from: processes)
    }

    /// 用一组"还活着"的 PID 修剪登记表（不传全机扫描结果，只传自己登记的探活结果）。
    public mutating func refresh(runningProcessIds: Set<ProcessIdentifier>) {
        let pruned = registry.filtered(processes, runningProcessIds: runningProcessIds)
        guard pruned.count != processes.count else { return }
        processes = pruned
        persist()
    }

    /// 待探活的登记项（`key → pid`）。
    public var registrations: [ManagedServerKey: ProcessIdentifier] { processes }

    /// 所有已登记的 PID（探活/停止用）。
    public func registeredProcessIds() -> [ProcessIdentifier] {
        Array(processes.values)
    }

    public mutating func removeProcess(for key: ManagedServerKey) {
        processes.removeValue(forKey: key)
        persist()
    }

    public mutating func removeAll() {
        processes.removeAll()
        persist()
    }
}
