//
//  SelfHostedServersModel.swift
//  OrzMC
//

import Foundation
import Observation
import OrzMCLauncher
import OrzMCProtocol

/// 自建服务器面板的状态：**多台档案** + 每台的实时状态 / 控制台。
///
/// 为什么一个模型管多台而不是"一台一个模型"：切换服务器时状态、控制台滚动位置、
/// 正在跑的探测任务都应该自然衔接（不是重建整个页面），而这些都需要一个统一的持有者。
/// 只有**当前选中**的那台在轮询状态；其余档案只保留上次结果，切回来时立刻有东西看。
@MainActor
@Observable
final class SelfHostedServersModel {

    struct ConsoleLine: Identifiable, Equatable {
        enum Kind: Equatable { case command, output, error }
        let id = UUID()
        let kind: Kind
        let text: String
    }

    /// 每台服务器最多留多少行控制台输出。
    private static let maxConsoleLines = 400

    private(set) var profiles: SelfHostedProfiles
    private(set) var status: [UUID: MCStatusSummary] = [:]
    private(set) var statusError: [UUID: String] = [:]
    private(set) var lastUpdatedAt: [UUID: Date] = [:]
    private(set) var consoleLines: [UUID: [ConsoleLine]] = [:]
    private(set) var isProbing = false
    private(set) var isSending = false
    var commandDraft = ""

    private let probe: MCServerProbe
    private let defaults: UserDefaults

    init(probe: MCServerProbe = MCServerProbe(), defaults: UserDefaults = .standard) {
        self.probe = probe
        self.defaults = defaults
        self.profiles = SelfHostedProfilesStore.load(defaults: defaults)
        if let first = profiles.servers.first {
            SelfHostedCredentials.migrateLegacyPasswordIfNeeded(to: first.id)
        }
    }

    // MARK: - 派生

    var selected: SelfHostedServerProfile? { profiles.selected }

    var canRunCommands: Bool {
        guard let selected else { return false }
        return selected.rconEnabled && selected.isConfigured
            && !(SelfHostedCredentials.password(for: selected.id) ?? "").isEmpty
    }

    var currentStatus: MCStatusSummary? { selected.flatMap { status[$0.id] } }
    var currentStatusError: String? { selected.flatMap { statusError[$0.id] } }
    var currentLastUpdatedAt: Date? { selected.flatMap { lastUpdatedAt[$0.id] } }
    var currentConsoleLines: [ConsoleLine] { selected.flatMap { consoleLines[$0.id] } ?? [] }

    var playersText: String? {
        guard let current = currentStatus,
              let online = current.playersOnline,
              let max = current.playersMax
        else { return nil }
        return String(localized: "\(online)/\(max) players")
    }

    // MARK: - 档案管理

    func select(_ id: UUID) {
        guard profiles.selectedID != id else { return }
        profiles.select(id)
        save()
    }

    /// 保存一台（新增或修改），并选中它。
    func save(_ profile: SelfHostedServerProfile, rconPassword: String? = nil) {
        profiles.upsert(profile)
        save()
        if let rconPassword {
            SelfHostedCredentials.save(rconPassword, for: profile.id)
        }
    }

    func remove(_ id: UUID) {
        profiles.remove(id: id)
        save()
        SelfHostedCredentials.remove(for: id)
        status[id] = nil
        statusError[id] = nil
        lastUpdatedAt[id] = nil
        consoleLines[id] = nil
    }

    private func save() {
        SelfHostedProfilesStore.save(profiles, defaults: defaults)
    }

    // MARK: - 状态

    /// 查一次当前服务器的状态。失败**不清空**上一次的展示（"暂时查不到"不该让卡片闪成空白）。
    func refreshStatus() async {
        guard let profile = selected, profile.isConfigured, !isProbing else { return }
        isProbing = true
        defer { isProbing = false }
        do {
            let summary = try await probe.status(host: profile.host, port: Int32(profile.port))
            status[profile.id] = summary
            statusError[profile.id] = nil
            lastUpdatedAt[profile.id] = .now
        } catch {
            statusError[profile.id] = Self.describe(error, address: profile.address)
        }
    }

    // MARK: - 控制台

    /// 发命令；返回是否真的发出去了（`false` = 缺密码/为空/正在发）。
    @discardableResult
    func sendCommand(_ raw: String? = nil) async -> Bool {
        guard let profile = selected else { return false }
        let command = (raw ?? commandDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !isSending else { return false }
        guard let password = SelfHostedCredentials.password(for: profile.id), !password.isEmpty else {
            append(.init(kind: .error, text: String(localized: "RCON password is missing. Add it in Settings.")), to: profile.id)
            return false
        }

        append(.init(kind: .command, text: "> \(command)"), to: profile.id)
        if raw == nil { commandDraft = "" }
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
            append(.init(kind: .output, text: trimmed.isEmpty ? String(localized: "(no output)") : trimmed), to: profile.id)
            return true
        } catch {
            let address = profile.rconPort == 25565 ? profile.host : "\(profile.host):\(profile.rconPort)"
            append(.init(kind: .error, text: Self.describe(error, address: address)), to: profile.id)
            return false
        }
    }

    func clearConsole() {
        guard let id = selected?.id else { return }
        consoleLines[id] = []
    }

    private func append(_ line: ConsoleLine, to id: UUID) {
        var lines = consoleLines[id] ?? []
        lines.append(line)
        if lines.count > Self.maxConsoleLines {
            lines.removeFirst(lines.count - Self.maxConsoleLines)
        }
        consoleLines[id] = lines
    }

    // MARK: - 错误文案

    /// 把网络/协议错误翻译成"一眼能懂"的一句话。
    /// 注意：**不要**把端口作为 `Int` 插值进本地化字符串——它会被按地区加千位分隔符
    /// （实测显示成 `127.0.0.1:25,565`）。这里统一用拼好的 `address` 字符串。
    private static func describe(_ error: Error, address: String) -> String {
        switch error {
        case MCStreamError.connectFailed:
            return String(localized: "Can't connect to \(address). Check the address, the port and your network.")
        case MCStreamError.connectionClosed:
            return String(localized: "The server closed the connection. Check that the port belongs to Minecraft, not another service.")
        case MCSLPError.pingFailed, MCSLPError.packetMalFormat:
            return String(localized: "The server answered in an unexpected format. Is it a Minecraft server?")
        case MCRCONError.authFailed:
            return String(localized: "RCON password was rejected. Check the password in server.properties.")
        case MCRCONError.responseInvalid, MCRCONError.packetMalFormat:
            return String(localized: "RCON answered in an unexpected format.")
        case MCProbeError.timedOut:
            return String(localized: "The server didn't answer in time. Check the address and that the port is open.")
        case is MCStatusError:
            return String(localized: "This server returned status data this app doesn't understand.")
        default:
            return error.localizedDescription
        }
    }
}
