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

    func stopAll() throws {
        try service.stop(processIds: service.pids())
        service.removeAll()
        refresh()
    }
}
