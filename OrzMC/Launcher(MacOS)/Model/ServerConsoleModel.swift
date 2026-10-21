//
//  ServerConsoleModel.swift
//  OrzMC
//

import Foundation
import JokerKits
import Observation
import OrzMCLauncher

/// 服务端控制台：显示运行期日志 + 接受用户输入的命令。
///
/// 数据流：
/// - 输出：引擎 `ServerInfo.onServerLog`（stdout+stderr 合流、按块）→ 本模型 `append`（去 ANSI、分行、限长）；
/// - 输入：用户在控制台敲命令 → `ManagedProcess.send`（OrzSwiftKit 0.18+，自动补 `\n`）。
///
/// 缓冲区与命令历史是纯逻辑（`ServerConsoleBuffer`，在 `Sources/OrzMCLauncher`，有单测），
/// 这里只负责和进程/UI 对接。
@MainActor
@Observable
final class ServerConsoleModel {

    private(set) var buffer = ServerConsoleBuffer()
    /// 当前有没有可以收命令的服务端进程（没有时输入框禁用）。
    private(set) var isAttached = false
    /// 正在跑的服务端标识（版本 + 核心），用于标题显示。
    private(set) var attachedLabel: String?

    /// 供 UI 逐条渲染。
    var lines: [ConsoleLine] { buffer.lines }
    var history: [String] { buffer.history }

    private var process: ManagedProcess?

    // MARK: 生命周期

    /// 服务端启动后挂上进程（之后日志会流进来、命令能送进去）。
    func attach(_ process: ManagedProcess, label: String) {
        self.process = process
        self.isAttached = true
        self.attachedLabel = label
        appendSystem("Attached to \(label) (pid \(process.processIdentifier))")
    }

    /// 进程退出/被停：解绑并 flush 残留半行。
    func detach(reason: String? = nil) {
        buffer.flush()
        if let reason { appendSystem(reason) }
        process = nil
        isAttached = false
        attachedLabel = nil
    }

    // MARK: 输出

    /// 引擎回调（可能来自任意线程/块大小）；主线程上并入缓冲。
    nonisolated func append(_ chunk: String) {
        Task { @MainActor [weak self] in
            self?.buffer.append(chunk)
        }
    }

    func appendSystem(_ text: String) {
        buffer.append("[OrzMC] \(text)\n")
    }

    // MARK: 输入

    /// 发送用户命令；返回是否送出（进程不在 → `false`，UI 会提示）。
    @discardableResult
    func send(_ raw: String) -> Bool {
        guard let command = buffer.submitCommand(raw) else { return false }
        guard let process, process.isRunning, process.send(command) else {
            appendSystem("Cannot send \"\(command)\": server is not running")
            return false
        }
        return true
    }

    /// 上/下方向键取历史。
    func historyEntry(at offset: Int) -> String? {
        buffer.historyEntry(at: offset)
    }

    func clear() {
        buffer.clear()
    }
}
