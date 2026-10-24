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

    /// 一台服务器的三份名单（都来自 RCON 的"人话回复"，由 `PlayerListParser` 解析）。
    struct PlayerLists: Equatable {
        var online: [String] = []
        var whitelisted: [String] = []
        var banned: [(name: String, reason: String?)] = []

        static func == (lhs: PlayerLists, rhs: PlayerLists) -> Bool {
            lhs.online == rhs.online
                && lhs.whitelisted == rhs.whitelisted
                && lhs.banned.map(\.name) == rhs.banned.map(\.name)
        }
    }

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
    /// 玩家名单（在线 / 白名单 / 封禁），按R CON 查询结果解析，同样按服务器分开存。
    private(set) var playerLists: [UUID: PlayerLists] = [:]
    private(set) var isFetchingLists = false
    private(set) var listError: [UUID: String] = [:]
    private(set) var isProbing = false
    private(set) var isSending = false
    var commandDraft = ""

    private let probe: MCServerProbe
    private let defaults: UserDefaults
    /// 状态变化通知（在线↔离线）。
    let notifier = ServerStatusNotifier()
    /// RCON 密码来源（默认读 Keychain）。做成可注入是为了**单测**能跑完整流程
    /// （Keychain 在测试环境不可用，也不该被测试写入）。
    private let passwordProvider: (UUID) -> String?

    init(
        probe: MCServerProbe = MCServerProbe(),
        defaults: UserDefaults = .standard,
        passwordProvider: @escaping (UUID) -> String? = { SelfHostedCredentials.password(for: $0) }
    ) {
        self.probe = probe
        self.defaults = defaults
        self.passwordProvider = passwordProvider
        self.profiles = SelfHostedProfilesStore.load(defaults: defaults)
        if let first = profiles.servers.first {
            SelfHostedCredentials.migrateLegacyPasswordIfNeeded(to: first.id)
        }
        #if DEBUG
        // UI 测试 / 截图验收用：`ORZMC_DEMO_SEED_PROFILE="名称|host|port|rconPort|0|1"` 注入一份内存档案
        // （不写 UserDefaults，避免污染真实配置）。配合 `scripts/test-servers/` 的假服务端即可断言整页。
        if let raw = ProcessInfo.processInfo.environment["ORZMC_DEMO_SEED_PROFILE"], !raw.isEmpty {
            let parts = raw.split(separator: "|").map(String.init)
            if parts.count >= 5 {
                let profile = SelfHostedServerProfile(
                    name: parts[0],
                    host: parts[1],
                    port: Int(parts[2]) ?? 25565,
                    rconPort: Int(parts[3]) ?? 25575,
                    rconEnabled: parts[4] == "1"
                )
                self.profiles = SelfHostedProfiles(servers: [profile], selectedID: profile.id)
            }
        }
        #endif
    }

    // MARK: - 派生

    var selected: SelfHostedServerProfile? { profiles.selected }

    var canRunCommands: Bool {
        guard let selected else { return false }
        return selected.rconEnabled && selected.isConfigured
            && !(passwordProvider(selected.id) ?? "").isEmpty
    }

    var currentStatus: MCStatusSummary? { selected.flatMap { status[$0.id] } }
    var currentStatusError: String? { selected.flatMap { statusError[$0.id] } }
    var currentLastUpdatedAt: Date? { selected.flatMap { lastUpdatedAt[$0.id] } }
    var currentConsoleLines: [ConsoleLine] { selected.flatMap { consoleLines[$0.id] } ?? [] }
    var currentLists: PlayerLists { selected.flatMap { playerLists[$0.id] } ?? PlayerLists() }

    /// 展示用的在线名单。
    ///
    /// 优先用 RCON `list` 的结果（最准）；**没有 RCON 时退回 SLP 的 sample**——
    /// 否则会出现"状态卡写着 2/20 名玩家、玩家卡却是 0"的自相矛盾（实测）。
    var currentOnlinePlayers: [String] {
        let fromRCON = currentLists.online
        if !fromRCON.isEmpty { return fromRCON }
        return currentStatus?.sampleNames ?? []
    }
    var currentListError: String? { selected.flatMap { listError[$0.id] } }

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
        playerLists[id] = nil
        listError[id] = nil
        notifier.forget(id)
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
            notifier.observe(profile, isOnline: true)
        } catch {
            statusError[profile.id] = SelfHostedErrorText.describe(error, address: profile.address)
            // 查询失败 = 连不上（离线）。**注意**：第一次查询就失败不弹通知（还没有基准）。
            notifier.observe(profile, isOnline: false)
        }
    }

    // MARK: - 控制台

    /// 发命令；返回是否真的发出去了（`false` = 缺密码/为空/正在发）。
    @discardableResult
    func sendCommand(_ raw: String? = nil) async -> Bool {
        guard let profile = selected else { return false }
        let command = (raw ?? commandDraft).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty, !isSending else { return false }
        guard let password = passwordProvider(profile.id), !password.isEmpty else {
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
            append(.init(kind: .error, text: SelfHostedErrorText.describe(error, address: address)), to: profile.id)
            return false
        }
    }

    /// 用 RCON 拉三份名单（`list` / `whitelist list` / `banlist list`）。
    ///
    /// 失败不打断页面：把原因写进 `listError`，界面上显示"未获取"。
    func refreshPlayerLists() async {
        // 没密码就直接跳过：界面已经有"需要密码"的提示，不必再连一次拿一个误导性的"密码被拒绝"。
        guard let profile = selected, profile.rconEnabled, canRunCommands, !isFetchingLists else { return }
        isFetchingLists = true
        defer { isFetchingLists = false }

        var lists = PlayerLists()
        do {
            let online = try await runCommand("list", profile: profile)
            lists.online = PlayerListParser.onlinePlayers(from: online)
            if let whitelist = try? await runCommand("whitelist list", profile: profile) {
                lists.whitelisted = PlayerListParser.whitelisted(from: whitelist)
            }
            if let bans = try? await runCommand("banlist list", profile: profile) {
                lists.banned = PlayerListParser.banned(from: bans)
            }
            playerLists[profile.id] = lists
            listError[profile.id] = nil
        } catch {
            listError[profile.id] = SelfHostedErrorText.describe(error, address: profile.address)
        }
    }

    /// 执行一条命令并返回原始回复（不写控制台记录——名单查询是后台动作）。
    private func runCommand(_ command: String, profile: SelfHostedServerProfile) async throws -> String {
        guard let password = passwordProvider(profile.id), !password.isEmpty else {
            throw MCRCONError.authFailed
        }
        return try await probe.runRCON(
            host: profile.host,
            port: Int32(profile.rconPort),
            password: password,
            command: command
        )
    }

    /// 玩家操作（踢出 / OP / 封禁 / 白名单…）：发命令并刷新名单，控制台里也能看到回显。
    func performPlayerAction(_ command: String) async {
        guard let profile = selected else { return }
        await sendCommand(command)
        await refreshPlayerLists()
        _ = profile
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

}
