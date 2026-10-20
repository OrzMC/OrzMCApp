//
//  CommandLineToolModel.swift
//  OrzMC
//
//  Created by pi on 2026/10/17.
//

import AppKit
import Foundation
import Game
import Observation
import OrzMCLauncher

/// GUI 侧的「命令行工具」状态与安装入口（D7：一个 `orzmc`，CLI 与 GUI 两面，
/// **可互相安装/打开**——`orzmc app` 打开 GUI，这里反过来装 CLI）。
///
/// 本类**不实现安装逻辑**：只调用官方安装器（Python / Swift 任一发布通道），
/// 并以 `ORZMC_SURFACE=gui` 让安装器把「哪个前端装的」写进 `install.conf`
/// （规范 `docs/spec/install-update.md` §3.1）。
///
/// **升级不走安装器**：`orzmc update` 会保留 `surface`/`source`（§3.1 / §9），
/// 所以在有真身时用 `update`，避免把「由终端安装」的记录静默改成「由本应用安装」。
@MainActor
@Observable
final class CommandLineToolModel {

    /// 两条**发布通道**（同一份规范的两个发布源，见 `docs/spec/frontends.md` F1/F3）。
    typealias Channel = InstallChannel

    /// GUI 对一条安装记录的只读视图（`nil` = 未安装/无记录）。
    typealias Status = InstallRecordView

    private(set) var status: Status?

    /// 安装 / 升级 / 卸载进行中（三者串行，避免同时动同一个真身）。
    private(set) var isBusy = false

    /// 子进程输出（stdout+stderr 合并，按行保存）。
    private(set) var log: [String] = []

    private(set) var errorMessage: String?

    // MARK: 读取

    /// 读 `install.conf`（状态目录；GUI 只读，不写）。
    func refresh() {
        guard let (path, manifest) = InstallManifest.current() else {
            status = nil
            return
        }
        status = Status(
            version: manifest.version,
            binaryPath: manifest.binary,
            surface: manifest.surface,
            source: manifest.source,
            completionFile: manifest.completionFile,
            recordPath: path,
            binaryExists: !manifest.binary.isEmpty
                && FileManager.default.isExecutableFile(atPath: manifest.binary)
        )
    }

    func revealBinary() {
        guard let path = status?.binaryPath, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func revealRecord() {
        guard let path = status?.recordPath else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: 安装 / 升级 / 卸载

    /// 调用官方安装器（`ORZMC_SURFACE=gui`），逐行回显输出。
    func install(_ channel: Channel) async {
        guard !isBusy else { return }
        isBusy = true
        errorMessage = nil
        log = ["$ \(channel.oneLiner)"]
        defer { isBusy = false }

        // 不用 `curl | sh`：先落盘再执行，失败点更明确，也不会把 curl 的退出码
        // 混进 sh 的退出码里。
        let script = """
        set -e
        tmp="$(mktemp "${TMPDIR:-/tmp}/orzmc-install.XXXXXX")"
        trap 'rm -f "$tmp"' EXIT
        curl -fsSL "$1" -o "$tmp"
        sh "$tmp"
        """

        let code = await run(
            executable: "/bin/sh",
            arguments: ["-c", script, "orzmc-gui-install", channel.installerURL],
            environment: InstallSurfacePolicy.installerEnvironment(
                base: ProcessInfo.processInfo.environment)
        )
        refresh()
        if code != 0 {
            errorMessage = "Installer failed (exit code \(code)); see the log above."
        }
    }

    /// 原地升级：走官方 `orzmc update`（保留 `surface` / `source`，规范 §3.1）。
    func update() async {
        guard !isBusy, let status else { return }
        isBusy = true
        errorMessage = nil
        log = ["$ orzmc update --yes"]
        defer { isBusy = false }

        guard status.canUpdateInPlace else {
            errorMessage = "The recorded binary is missing; reinstall instead."
            return
        }
        let code = await run(executable: status.binaryPath, arguments: ["update", "--yes"])
        refresh()
        if code != 0 {
            errorMessage = "Update failed (exit code \(code)); see the log above."
        }
    }

    /// 卸载：走官方 `orzmc uninstall --yes`（规范 §9），记录随之删除。
    func uninstall() async {
        guard !isBusy, let status else { return }
        isBusy = true
        errorMessage = nil
        log = ["$ orzmc uninstall --yes"]
        defer { isBusy = false }

        guard status.canUpdateInPlace else {
            errorMessage = "The recorded binary is missing; remove install.conf manually if needed."
            return
        }
        let code = await run(executable: status.binaryPath, arguments: ["uninstall", "--yes"])
        refresh()
        if code != 0 {
            errorMessage = "Uninstall failed (exit code \(code)); see the log above."
        }
    }

    // MARK: 子进程

    private func run(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil
    ) async -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            errorMessage = "Cannot start \(executable): \(error.localizedDescription)"
            log.append("start failed: \(error.localizedDescription)")
            return -1
        }

        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                appendLine(line)
            }
        } catch {
            log.append("read failed: \(error.localizedDescription)")
        }

        process.waitUntilExit()
        let code = process.terminationStatus
        log.append("exit code: \(code)")
        return code
    }

    private func appendLine(_ line: String) {
        // 安装器的进度条用 `\r` 自刷新，这里只保留有内容的整行。
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        log.append(trimmed)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }
}

// MARK: - 通道的展示信息（GUI 专属：安装器地址与一行命令）

extension CommandLineToolModel.Channel: @retroactive Identifiable {
    public var id: String { rawValue }

    /// 官方安装器地址（与各仓库 README 上的一行命令一致）。
    var installerURL: String {
        switch self {
        case .python:
            return "https://orzmc.github.io/OrzPythonMC/install.sh"
        case .swift:
            return "https://raw.githubusercontent.com/OrzMC/OrzMCKit/main/scripts/install.sh"
        }
    }

    var oneLiner: String {
        "curl -fsSL \(installerURL) | sh"
    }
}
