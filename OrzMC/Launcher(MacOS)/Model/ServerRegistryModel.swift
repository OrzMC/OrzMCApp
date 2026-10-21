//
//  ServerRegistryModel.swift
//  OrzMC
//

import Foundation
import Observation
import OrzMCLauncher

/// 服务端进程登记表：**只认自己启动过的**（落盘 + `kill(pid, 0)` 探活）。
@MainActor
@Observable
final class ServerRegistryModel {

    private(set) var alivePids: Set<String> = []

    private var service = ServerProcessService()

    var hasRunning: Bool { !alivePids.isEmpty }

    func record(_ launched: LaunchedServer) {
        service.record(launched)
        refresh()
    }

    /// 探活已登记的进程（无子进程、不碰别人的进程）。
    func refresh() {
        service.refreshAliveness()
        alivePids = service.aliveRegisteredPids()
    }

    /// 周期探活（2s）。由场景在窗口出现时启动，取消时退出。
    func monitor() async {
        while !Task.isCancelled {
            refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func pid(versionId: String, software: SettingsModel.ServerSoftware) -> String? {
        service.pid(versionId: versionId, software: software)
    }

    func isRunning(versionId: String, software: SettingsModel.ServerSoftware) -> Bool {
        guard let pid = pid(versionId: versionId, software: software) else { return false }
        return alivePids.contains(pid)
    }

    func stop(versionId: String, software: SettingsModel.ServerSoftware) throws {
        guard let pid = pid(versionId: versionId, software: software) else { return }
        try service.stop(processId: pid)
        service.remove(versionId: versionId, software: software)
        refresh()
    }

    /// 进程已自己退出：只清登记（不要再去 kill 一个死进程）。
    func remove(versionId: String, software: SettingsModel.ServerSoftware) {
        service.remove(versionId: versionId, software: software)
        refresh()
    }

    /// 当前活着的实例：`[(versionId, software)]`，供「停止全部」逐个走优雅停止。
    func runningInstances() -> [(versionId: String, software: SettingsModel.ServerSoftware)] {
        service.aliveRegistrations().compactMap { registration in
            let parts = registration.key.split(separator: "#", maxSplits: 1)
            guard parts.count == 2,
                  let software = SettingsModel.ServerSoftware(rawValue: String(parts[1]))
            else { return nil }
            return (String(parts[0]), software)
        }
    }

    /// 无句柄的「终止」：`SIGTERM` → 超时 `SIGKILL`。
    func terminate(versionId: String, software: SettingsModel.ServerSoftware) throws {
        guard let pid = pid(versionId: versionId, software: software) else { return }
        try service.terminate(processId: pid)
        service.remove(versionId: versionId, software: software)
        refresh()
    }

    func stopAll() throws {
        try service.stop(processIds: service.pids())
        service.removeAll()
        refresh()
    }
}
