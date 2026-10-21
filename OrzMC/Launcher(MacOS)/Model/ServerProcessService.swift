//
//  ServerProcessService.swift
//  OrzMC
//
//  Created by Codex on 2026/5/23.
//

import Darwin
import Foundation
import JokerKits
import OrzMCFoundation
import OrzMCLauncher

/// 只做「停一个 PID」——**不再做全机进程扫描**。
///
/// 旧实现每轮 `Shell.allRunningServerPids()`（= `ps` 全机搜索 `nogui`）来"发现"服务端，
/// 于是把**别人启动的**服务端也算成自己的，`Stop All` 会误杀；而且每秒一次子进程。
protocol ServerProcessCommanding: AnyObject {
    func stop(processId: String) throws
    /// 强制终止：`SIGTERM` → 等 `graceSeconds` → 还在就 `SIGKILL`。
    func terminate(processId: String, graceSeconds: Int) throws
}

final class ShellServerProcessCommander: ServerProcessCommanding {
    func stop(processId: String) throws {
        try Shell.runCommand(with: ["kill", processId])
    }

    /// 先 `TERM` 给 JVM 一个跑 shutdown hook（存档）的机会，超时才 `KILL`。
    ///
    /// 这是**没有进程句柄**时能做到的最好情况：App 重启后接管上个会话启动的服务端，
    /// stdin 管道早没了，送不进 `stop` 命令，只能发信号。
    func terminate(processId: String, graceSeconds: Int) throws {
        try Shell.runCommand(with: ["kill", "-TERM", processId])
        let deadline = Date().addingTimeInterval(TimeInterval(graceSeconds))
        while Date() < deadline {
            if !Self.isAlive(processId: processId) { return }
            Thread.sleep(forTimeInterval: 0.2)
        }
        try Shell.runCommand(with: ["kill", "-KILL", processId])
    }

    private static func isAlive(processId: String) -> Bool {
        guard let pid = Int32(processId) else { return false }
        return kill(pid, 0) == 0
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

    /// 活着的登记（`版本#核心` → PID），供「停止全部」逐个处理。
    func aliveRegistrations() -> [(key: String, pid: String)] {
        store.registrations
            .filter { probe.isAlive($0.value) }
            .map { (key: $0.key.rawValue, pid: $0.value.rawValue) }
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

    /// 强制终止（无句柄场景的「终止」）。
    func terminate(processId: String, graceSeconds: Int = 10) throws {
        try commander.terminate(processId: processId, graceSeconds: graceSeconds)
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
