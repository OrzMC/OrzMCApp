//
//  ExarotonContent.swift
//  OrzMC
//
//  Created by joker on 2024/5/22.
//

import SwiftUI

struct ExarotonContent: View {
    @State private var model = ExarotonServerModel()
    /// MCSManager 面板（P2-7 第 4 步）：与 exaroton **同一页按供应商分组**。
    @State private var mcsm = MCSManagerPanelsModel()
    @Environment(\.scenePhase) private var scenePhase

    #if DEBUG
    /// **诊断钩子**（仅 DEBUG）：`ORZMC_DEMO_DIAGNOSE=1` 启动后自动连第一台服务器，把 WS/ready/流/控制台
    /// 状态写成 `Documents/orzmc-diagnose.json`。用于真机排查"在线但控制台连不上"——
    /// 真机不能点屏幕，但可以用 `devicectl device copy` 把这个文件取回来。
    private func runDiagnosticsIfRequested() async {
        guard let mode = ProcessInfo.processInfo.environment["ORZMC_DEMO_DIAGNOSE"], mode != "0" else { return }
        await model.reloadList()
        guard let server = model.servers.first, let id = server.id else { return }
        // `ORZMC_DEMO_DIAGNOSE=start`：顺便把这台服务器启动起来，用来验证"在线 → 有流 → 控制台有日志"。
        var startResult = "-"
        if mode == "start" {
            let ok = await model.startServer(serverId: id)
            startResult = ok ? "ok" : "false · \(model.actionErrors[id] ?? model.actionMessages[id] ?? "-")"
        }
        model.startConnect(for: id)

        var report: [[String: String]] = []
        for step in 0..<12 {
            try? await Task.sleep(for: .seconds(5))
            report.append([
                "t": "\(step * 5)s",
                "isConnected": String(model.isConnected),
                "isLive": String(model.isLive),
                "readyServerID": model.readyServerID ?? "-",
                "expectedServerID": id,
                "activeStreams": model.activeStreams.map(\.rawValue).sorted().joined(separator: ","),
                "consoleLines": String(model.consoleLines.count),
                "disconnectedReason": model.disconnectedReason ?? "-",
                "errorMessage": model.errorMessage ?? "-",
                "status": Self.describe(model.effectiveStatus(for: server)),
                "liveStatus": Self.describe(model.servers.first.flatMap { model.effectiveStatus(for: $0) }),
                "startError": model.actionErrors[id] ?? "-",
                "startResult": startResult,
                "actionLog": ExarotonServerModel.debugActionLog.joined(separator: " | "),
            ])
        }
        let json = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("orzmc-diagnose.json")
        try? json?.write(to: url)
    }

    private static func describe(_ status: ServerStatus?) -> String {
        guard let status else { return "-" }
        return String(describing: status)
    }
    #endif
    var body: some View {
        NavigationStack(path: $model.path) {
            ExarotonServerList()
                .environment(model)
                .environment(mcsm)
        }
        .alert("Remote Server Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(verbatim: model.errorMessage ?? "")
        }
        // 后台状态轮询由**模型**持有（不是视图）：切到别的页签、进出详情都不会中断，
        // 否则服务器自动关机后界面会一直停在「在线」（真机反馈）。
        .task { model.startBackgroundRefresh() }
        .onChange(of: scenePhase) { _, phase in
            model.isSceneActive = phase == .active
            mcsm.isSceneActive = phase == .active
            // 回到前台立刻拉一次：后台期间状态可能已经变了。
            if phase == .active, !model.token.isEmpty {
                Task { await model.reloadList() }
            }
        }
        #if DEBUG
        .task { await runDiagnosticsIfRequested() }
        #endif
    }
}

#Preview {
    ExarotonContent()
}
