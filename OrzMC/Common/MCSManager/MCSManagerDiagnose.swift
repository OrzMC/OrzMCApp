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

    /// 可选：`ORZMC_DEMO_MCSM_RAW_LOG=1` —— 把每台实例的**原始**控制台尾部（含所有转义序列）
    /// 逐字节写进 Caches，用来定位"终端重绘被解析坏"的真因。
    ///
    /// 为什么不靠截图：`> versioversion` 这种现象可能是 `\b`、CSI 光标移动、`\r` 覆盖任一组合
    /// 造成的，只有原始字节能区分（2026-11-05：`lislist` 修好后仍有 `versioversion`）。
    /// **只读**：只调 `outputlog` 拉尾部，不发任何命令。
    static let rawLogKey = "ORZMC_DEMO_MCSM_RAW_LOG"

    static var isRequested: Bool {
        let environment = ProcessInfo.processInfo.environment
        // `RAW_LOG` 单独出现也算"要跑"：定位解析问题时往往只想拿原始字节、不想再看一遍汇总。
        return environment[environmentKey] == "1" || environment[rawLogKey] == "1"
    }

    /// 由 `OrzMCApp.init()` 触发（两端通用）。
    static func runIfRequested() async {
        guard isRequested else { return }

        let model = MCSManagerPanelsModel()
        model.isSceneActive = true

        // 先落一条"我跑起来了 + 看到了哪些开关"的记录：`open --env` 在某些 macOS 版本上
        // 会悄悄丢环境变量，没有这条记录就分不清"没跑"和"跑了但没数据"。
        writeRunRecord(panels: model.panels.count)

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
                if ProcessInfo.processInfo.environment[rawLogKey] == "1" {
                    await dumpRawConsole(panelModel, panel: panel)
                }
                // 成功时 reload 里已经写过；这里补写一次带上最终的错误文案。
                panelModel.writeDiagnose(error: panelModel.errorMessage)
            }
        }

        // 给写入留一点时间，然后退出（脚本据此判断"跑完了"）。
        try? await Task.sleep(for: .seconds(2))
        exit(0)
    }

    /// 诊断入口的自述：环境里的每个 `ORZMC_DEMO_*` 开关 + 读到几个面板。
    @MainActor
    private static func writeRunRecord(panels: Int) {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let environment = ProcessInfo.processInfo.environment
            .filter { $0.key.hasPrefix("ORZMC_DEMO_") }
            .sorted { $0.key < $1.key }
        let snapshot: [String: Any] = [
            "at": ISO8601DateFormatter().string(from: Date()),
            "panels": panels,
            "environment": Dictionary(uniqueKeysWithValues: environment),
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: snapshot,
            options: [.prettyPrinted, .sortedKeys]
        ) else { return }
        try? data.write(to: directory.appendingPathComponent("orzmc-mcsm-run.json"))
    }

    /// 把每台实例的**原始**控制台尾部写成文本（仅 DEBUG 诊断用）。
    ///
    /// 用 `.txt` 而不是 JSON：终端输出里可能有让 `JSONSerialization` 直接失败的内容，
    /// 诊断代码本身不应该再引入一层失败可能。
    @MainActor
    private static func dumpRawConsole(_ model: MCSManagerModel, panel: MCSManagerPanel) async {
        guard let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return
        }
        let instances = model.instances
        var summary = "panel=\(panel.label) instances=\(instances.count) error=\(model.errorMessage ?? "-")\n"
        for instance in instances {
            do {
                let text = try await model.outputLog(for: instance, tailSize: 32 * 1024)
                let escaped = escapedForDiagnose(text)
                let header = "instance=\(instance.nickname) id=\(instance.id) bytes=\(text.utf8.count)\n"
                // 实例 id 形如 `daemon/uuid`，直接当文件名会写入子目录并静默失败。
                let safeID = instance.id.replacingOccurrences(of: "/", with: "_")
                let name = "orzmc-mcsm-raw-\(safeID).txt"
                try? (header + escaped).write(
                    to: directory.appendingPathComponent(name),
                    atomically: true,
                    encoding: .utf8
                )
                summary += "  \(instance.nickname): bytes=\(text.utf8.count)\n"
            } catch {
                summary += "  \(instance.nickname): error=\(MCSManagerErrorText.describe(error) ?? String(describing: error))\n"
            }
        }
        try? summary.write(
            to: directory.appendingPathComponent("orzmc-mcsm-raw-summary.txt"),
            atomically: true,
            encoding: .utf8
        )
    }

    /// 把控制字符写成可读形式（`\u{1B}[1D`、`\b`、`\r`），保留普通文本。
    private static func escapedForDiagnose(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.utf8.count * 2)
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\u{1B}": result += "\\u{1B}"
            case "\u{08}": result += "\\b"
            case "\r": result += "\\r"
            case "\n": result += "\\n\n"
            case "\t": result += "\\t"
            default:
                if scalar.value < 0x20 || scalar.value == 0x7F {
                    result += String(format: "\\u{%02X}", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result
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
