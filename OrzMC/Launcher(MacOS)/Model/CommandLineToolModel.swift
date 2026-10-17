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

/// GUI 侧的「命令行工具」状态与安装入口（D7：一个 `orzmc`，CLI 与 GUI 两面，
/// **可互相安装/打开**——`orzmc app` 打开 GUI，这里反过来装 CLI）。
///
/// 本类**不实现安装逻辑**：只调用官方安装器（Python / Swift 任一发布通道），
/// 并以 `ORZMC_SURFACE=gui` 让安装器把「哪个前端装的」写进 `install.conf`
/// （规范 `docs/spec/install-update.md` §3.1）。
@MainActor
@Observable
final class CommandLineToolModel {

    /// 两个**发布通道**（不是两套格式）：同一份规范、同一套落点，
    /// 见 `docs/spec/frontends.md` F1/F3。
    enum Channel: String, CaseIterable, Identifiable {
        case python
        case swift

        var id: String { rawValue }

        var title: String {
            switch self {
            case .python: return "Python CLI"
            case .swift: return "Swift CLI"
            }
        }

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

    /// `install.conf` 的界面视图（`nil` = 未安装/无记录）。
    struct Status: Equatable {
        let version: String
        let binaryPath: String
        /// `cli` / `gui` / `nil`（旧记录，未知）。规范 §3.1。
        let surface: String?
        let source: String?
        let binaryExists: Bool

        var surfaceText: String {
            switch surface {
            case "gui": return "installed from this app"
            case "cli": return "installed from a terminal"
            default: return "origin unknown (legacy record)"
            }
        }
    }

    private(set) var status: Status?

    private(set) var isInstalling = false

    /// 安装器输出（stdout+stderr 合并，按行保存）。
    private(set) var log: [String] = []

    private(set) var errorMessage: String?

    // MARK: 读取

    /// 读 `install.conf`（状态目录；GUI 只读，不写）。
    func refresh() {
        guard let (_, manifest) = InstallManifest.current() else {
            status = nil
            return
        }
        status = Status(
            version: manifest.version,
            binaryPath: manifest.binary,
            surface: manifest.surface,
            source: manifest.source,
            binaryExists: !manifest.binary.isEmpty
                && FileManager.default.isExecutableFile(atPath: manifest.binary)
        )
    }

    func revealBinary() {
        guard let path = status?.binaryPath, !path.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    // MARK: 安装

    /// 调用官方安装器（`ORZMC_SURFACE=gui`），逐行回显输出。
    func install(_ channel: Channel) async {
        guard !isInstalling else { return }
        isInstalling = true
        errorMessage = nil
        log = ["$ \(channel.oneLiner)"]
        defer { isInstalling = false }

        // 不用 `curl | sh`：先落盘再执行，失败点更明确，也不会把 curl 的退出码
        // 混进 sh 的退出码里。
        let script = """
        set -e
        tmp="$(mktemp "${TMPDIR:-/tmp}/orzmc-install.XXXXXX")"
        trap 'rm -f "$tmp"' EXIT
        curl -fsSL "$1" -o "$tmp"
        ORZMC_SURFACE=gui sh "$tmp"
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script, "orzmc-gui-install", channel.installerURL]
        var environment = ProcessInfo.processInfo.environment
        environment["ORZMC_SURFACE"] = "gui"
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        process.standardInput = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            errorMessage = "无法启动安装器：\(error.localizedDescription)"
            log.append("启动失败：\(error.localizedDescription)")
            return
        }

        do {
            for try await line in pipe.fileHandleForReading.bytes.lines {
                appendLine(line)
            }
        } catch {
            log.append("读取安装器输出失败：\(error.localizedDescription)")
        }

        process.waitUntilExit()
        let code = process.terminationStatus
        log.append("退出码：\(code)")
        refresh()
        if code != 0 {
            errorMessage = "安装器失败（退出码 \(code)），详情见日志"
        }
    }

    private func appendLine(_ line: String) {
        // 安装器的进度条用 `\r` 自刷新，这里只保留有内容的整行。
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        log.append(trimmed)
        if log.count > 400 { log.removeFirst(log.count - 400) }
    }
}
