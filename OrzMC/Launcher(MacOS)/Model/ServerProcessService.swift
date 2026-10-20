//
//  ServerProcessService.swift
//  OrzMC
//
//  Created by Codex on 2026/5/23.
//

import JokerKits
import OrzMCFoundation
import OrzMCLauncher

/// 只做「停一个 PID」——**不再做全机进程扫描**。
///
/// 旧实现每轮 `Shell.allRunningServerPids()`（= `ps` 全机搜索 `nogui`）来"发现"服务端，
/// 于是把**别人启动的**服务端也算成自己的，`Stop All` 会误杀；而且每秒一次子进程。
protocol ServerProcessCommanding: AnyObject {
    func stop(processId: String) throws
}

final class ShellServerProcessCommander: ServerProcessCommanding {
    func stop(processId: String) throws {
        try Shell.runCommand(with: ["kill", processId])
    }
}

struct ServerProcessService {
    /// 登记表落盘（app 重启后仍记得自己启动过哪些服务端）。
    private var store = ManagedServerProcessStore(
        persistence: FileServerProcessPersistence()
    )
    private let commander: ServerProcessCommanding
    private let probe: ProcessLivenessProbing

    init(
        commander: ServerProcessCommanding = ShellServerProcessCommander(),
        probe: ProcessLivenessProbing = KernelProcessLivenessProbe(),
        persistence: ServerProcessPersisting? = FileServerProcessPersistence()
    ) {
        self.commander = commander
        self.probe = probe
        self.store = ManagedServerProcessStore(persistence: persistence)
    }

    func key(versionId: String, software: SettingsModel.ServerSoftware) -> String {
        ManagedServerKey(versionId: versionId, softwareId: software.rawValue).rawValue
    }

    mutating func record(_ launchedServer: LaunchedServer) {
        store.record(
            ProcessIdentifier(launchedServer.pid),
            for: ManagedServerKey(versionId: launchedServer.versionId, softwareId: launchedServer.software.rawValue)
        )
    }

    /// 探活**已登记**的进程（`kill(pid, 0)`，无子进程）；死掉的顺手从登记表移除。
    mutating func refreshAliveness() {
        let alive = Set(store.registeredProcessIds().filter { probe.isAlive($0) })
        store.refresh(runningProcessIds: alive)
    }

    /// 已登记的 PID 里仍然活着的（供 UI 显示/停止）。
    func aliveRegisteredPids() -> Set<String> {
        Set(
            store.registeredProcessIds()
                .filter { probe.isAlive($0) }
                .map(\.rawValue)
        )
    }

    var hasManagedRunningServers: Bool {
        store.hasManagedRunningServers
    }

    func pids() -> [String] {
        store.processIds().map(\.rawValue)
    }

    func pid(versionId: String, software: SettingsModel.ServerSoftware) -> String? {
        store.processId(for: ManagedServerKey(versionId: versionId, softwareId: software.rawValue))?.rawValue
    }

    mutating func remove(versionId: String, software: SettingsModel.ServerSoftware) {
        store.removeProcess(for: ManagedServerKey(versionId: versionId, softwareId: software.rawValue))
    }

    func stop(processId: String) throws {
        try commander.stop(processId: processId)
    }

    func stop(processIds: [String]) throws {
        for pid in processIds {
            try stop(processId: pid)
        }
    }

    mutating func removeAll() {
        store.removeAll()
    }
}
