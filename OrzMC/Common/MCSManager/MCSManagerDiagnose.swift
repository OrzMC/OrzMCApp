//
//  MCSManagerDiagnose.swift
//  OrzMC
//
//  **仅 DEBUG** 的无界面验收：`ORZMC_DEMO_MCSM_DIAGNOSE=1` 时启动后立刻把所有面板拉一遍，
//  结果写进 Caches（每个面板一个 `orzmc-mcsm-<id>.json`），然后退出。
//
//  为什么需要它：
//  - macOS 上 `screencapture` 要屏幕录制权限（agent 会话拿不到），远程托管又在**辅助窗口**里，
//    `osascript` 点窗口还要辅助功能权限；
//  - iPhone SE 上 MCSM 分组在折叠线下，截图看不到实例行。
//  有这个钩子就能直接核对「角色 / 实例数 / 每台实例的归一化状态 / 失败原因」。
//

#if DEBUG
import Foundation

@MainActor
enum MCSManagerDiagnose {

    static let environmentKey = "ORZMC_DEMO_MCSM_DIAGNOSE"

    /// 可选：`ORZMC_DEMO_MCSM_ACTION_PROBE="/list"` —— 对每台**在线**实例发这条命令，
    /// 并把控制台尾部写进诊断文件。
    ///
    /// 只用来验收"动作 + 控制台"链路（`sendCommand` → 面板 → `outputlog`）。
    /// **务必用只读命令**（`/list`、`/tps`），别用会改服务器状态的（`stop`、`/kick`）。
    static let actionProbeKey = "ORZMC_DEMO_MCSM_ACTION_PROBE"

    /// 可选：`ORZMC_DEMO_MCSM_STREAM_PROBE=1` —— 对每台**在线**实例跑一次实时流
    /// （申请通道 → 连 socket.io → 等 `stream/auth` → 发一条 `/list` → 等输出），
    /// 结果写进诊断文件的 `stream` 字段。
    ///
    /// 为什么需要它：实时流"能不能连上"取决于面板 `dataPlane` 与节点是否可达，
    /// 只有真面板能回答；而界面上它失败时会**静默回退轮询**（这是设计），
    /// 所以必须有一条不依赖截图的自检。
    static let streamProbeKey = "ORZMC_DEMO_MCSM_STREAM_PROBE"

    static var isRequested: Bool {
        ProcessInfo.processInfo.environment[environmentKey] == "1"
    }

    /// 由 `OrzMCApp.init()` 触发（两端通用）。
    static func runIfRequested() async {
        guard isRequested else { return }

        let model = MCSManagerPanelsModel()
        model.isSceneActive = true

        if model.panels.isEmpty {
            writeSummary(error: "no MCSManager panel configured")
        } else {
            await model.reloadAll()
            let probe = ProcessInfo.processInfo.environment[actionProbeKey]
            for panel in model.panels {
                guard let panelModel = model.model(for: panel.id) else { continue }
                if let probe, !probe.isEmpty {
                    await panelModel.probeCommands(probe)
                }
                if ProcessInfo.processInfo.environment[streamProbeKey] == "1" {
                    await panelModel.probeStream()
                }
                // 成功时 reload 里已经写过；这里补写一次带上最终的错误文案。
                panelModel.writeDiagnose(error: panelModel.errorMessage)
            }
        }

        // 给写入留一点时间，然后退出（脚本据此判断"跑完了"）。
        try? await Task.sleep(for: .seconds(2))
        exit(0)
    }

    /// 一个面板都没配时也留个文件，免得"没文件"被误读成"没跑"。
    private static func writeSummary(error: String) {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let snapshot: [String: Any] = ["at": ISO8601DateFormatter().string(from: Date()), "error": error]
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.prettyPrinted]) else {
            return
        }
        try? data.write(to: directory.appendingPathComponent("orzmc-mcsm-nopanel.json"))
    }
}
#endif
