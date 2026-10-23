//
//  SelfHostedServerModel.swift
//  OrzMC
//

import Foundation
import Observation
import OrzMCProtocol

/// 自建服务器面板的状态：状态查询（SLP）+ 控制台（RCON）。
///
/// 只有**一个**档案（P3 最小闭环）：够用来"看看自己服务器在不在线、踢个人、发条广播"。
/// 传输层在 `OrzMCProtocol.MCServerProbe` 里（可注入，单测不用网络）。
@MainActor
@Observable
final class SelfHostedServerModel {

    struct ConsoleLine: Identifiable, Equatable {
        enum Kind: Equatable { case command, output, error }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    /// 控制台最多留多少行（再多人也不会把内存吃满）。
    private static let maxConsoleLines = 400

    var profile: SelfHostedServerProfile {
        didSet {
            guard profile != oldValue else { return }
            profile.save()
            reloadRCONPassword()
        }
    }

    /// RCON 密码缓存：读 Keychain 是同步 IO，`canRunCommands` 在 body 里被反复求值，
    /// 不能每次渲染都去敲一次钥匙串。设置页保存后经 `profile.didSet` 刷新这里。
    private(set) var rconPassword: String?

    private(set) var status: MCStatusSummary?
    private(set) var isProbing = false
    private(set) var statusError: String?
    private(set) var lastUpdatedAt: Date?

    private(set) var consoleLines: [ConsoleLine] = []
    private(set) var isSending = false
    var commandDraft = ""

    private let probe: MCServerProbe

    init(profile: SelfHostedServerProfile = .load(), probe: MCServerProbe = MCServerProbe()) {
        self.profile = profile
        self.probe = probe
        self.rconPassword = SelfHostedServerProfile.rconPassword()
    }

    func reloadRCONPassword() {
        rconPassword = SelfHostedServerProfile.rconPassword()
    }

    // MARK: 派生状态

    var isOnline: Bool { status != nil }

    var canRunCommands: Bool {
        profile.rconEnabled && profile.isConfigured && !(rconPassword ?? "").isEmpty
    }

    var playersText: String? {
        guard let status, let online = status.playersOnline, let max = status.playersMax else { return nil }
        return String(localized: "\(online)/\(max) players")
    }

    // MARK: 状态

    /// 查一次状态。失败不清空上一次的展示（"暂时查不到"不该让卡片闪成空白）。
    func refreshStatus() async {
        guard profile.isConfigured, !isProbing else { return }
        isProbing = true
        defer { isProbing = false }
        do {
            let summary = try await probe.status(host: profile.host, port: Int32(profile.port))
            status = summary
            statusError = nil
            lastUpdatedAt = .now
        } catch {
            statusError = Self.describe(error, host: profile.host, port: profile.port)
        }
    }

    // MARK: 控制台

    func sendCommand() async {
        let command = commandDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !isSending else { return }
        guard let password = rconPassword, !password.isEmpty else {
            append(.init(kind: .error, text: String(localized: "RCON password is missing. Add it in Settings.")))
            return
        }

        append(.init(kind: .command, text: "> \(command)"))
        commandDraft = ""
        isSending = true
        defer { isSending = false }

        do {
            let reply = try await probe.runRCON(
                host: profile.host,
                port: Int32(profile.rconPort),
                password: password,
                command: command
            )
            let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
            append(.init(kind: .output, text: trimmed.isEmpty ? String(localized: "(no output)") : trimmed))
        } catch {
            append(.init(kind: .error, text: Self.describe(error, host: profile.host, port: profile.rconPort)))
        }
    }

    func clearConsole() {
        consoleLines.removeAll()
    }

    private func append(_ line: ConsoleLine) {
        consoleLines.append(line)
        if consoleLines.count > Self.maxConsoleLines {
            consoleLines.removeFirst(consoleLines.count - Self.maxConsoleLines)
        }
    }

    // MARK: 错误文案

    /// 把网络/协议错误翻译成"用户在手机上一眼能懂"的一句话。
    private static func describe(_ error: Error, host: String, port: Int) -> String {
        switch error {
        case MCStreamError.connectFailed:
            return String(localized: "Can't connect to \(host):\(port). Check the address, the port and your network.")
        case MCStreamError.connectionClosed:
            return String(localized: "The server closed the connection. Check that the port belongs to Minecraft, not another service.")
        case MCSLPError.pingFailed, MCSLPError.packetMalFormat:
            return String(localized: "The server answered in an unexpected format. Is it a Minecraft server?")
        case MCRCONError.authFailed:
            return String(localized: "RCON password was rejected. Check the password in server.properties.")
        case MCRCONError.responseInvalid, MCRCONError.packetMalFormat:
            return String(localized: "RCON answered in an unexpected format.")
        case is MCStatusError:
            return String(localized: "This server returned status data this app doesn't understand.")
        default:
            return error.localizedDescription
        }
    }
}
