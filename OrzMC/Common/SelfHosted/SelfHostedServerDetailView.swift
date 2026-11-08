//
//  SelfHostedServerDetailView.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCLauncher
import OrzMCProtocol
import SwiftUI

/// 「我的服务器」**详情页**：状态卡 + 玩家名单 + 控制台（RCON）。
///
/// 从列表页（`SelfHostedServerView`）点卡片进来。这些内容以前平铺在列表下面，
/// 导致"列表 + 详情"混在一屏、换服务器时整页重排；现在按远程托管页的规则拆开：
/// **列表只回答"有哪些服务器、它们现在怎么样"，详情才回答"对这台做什么"**。
struct SelfHostedServerDetailView: View {
    let profileID: UUID
    @Bindable var model: SelfHostedServersModel

    /// 正在编辑的档案（设置 sheet）。
    @State private var editing: SelfHostedServerProfile?
    @FocusState private var commandFocused: Bool
    @State private var playerListTab: PlayerListTab = .online
    @State private var playerNameDraft = ""
    @State private var consoleSearch = ""
    @AppStorage("console.wrapLines") private var wrapConsoleLines = false

    enum PlayerListTab: Hashable {
        case online
        case whitelist
        case banned
    }

    /// 档案可能被删掉（例如在设置里删除后返回）：这时给一个明确的空页，而不是崩在强制解包上。
    private var profile: SelfHostedServerProfile? {
        model.profiles.servers.first(where: { $0.id == profileID })
    }

    private var filteredConsoleLines: [SelfHostedServersModel.ConsoleLine] {
        let query = consoleSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return model.currentConsoleLines }
        return model.currentConsoleLines.filter {
            $0.segments.map(\.text).joined().localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        Group {
            if let profile {
                content(profile)
            } else {
                EmptyContentView(
                    ContentState(
                        title: String(localized: "Server removed"),
                        message: String(localized: "This server is no longer in your list."),
                        systemImage: "server.rack"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(profile?.displayName ?? String(localized: "My Server"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task {
                        await model.refreshStatus()
                        if model.canRunCommands { await model.refreshPlayerLists() }
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(profile?.isConfigured != true || model.isProbing)
                .help("Check the server status now")
                .accessibilityIdentifier("selfHosted.refresh")

                Button {
                    if let profile { editing = profile }
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .help("Server address, port and RCON")
                .accessibilityIdentifier("selfHosted.settings")
            }
        }
        .sheet(item: $editing) { profile in
            SelfHostedServerSettingsView(profile: profile) { updated, password, delete in
                if delete {
                    model.remove(updated.id)
                } else {
                    model.save(updated, rconPassword: password)
                    Task { await model.refreshStatus() }
                }
                editing = nil
            }
        }
        // 进来就选中这台：`current*` 系列访问器都基于选中项（控制台滚动位置、名单、探测结果）。
        .task(id: profileID) {
            model.select(profileID)
            await model.refreshStatus()
            if model.canRunCommands { await model.refreshPlayerLists() }
        }
        // 页面可见时每 20s 刷一次（比手动点慢得多，够用且省电）。
        .task(id: profileID) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard model.selected?.id == profileID, model.selected?.isConfigured == true else { continue }
                await model.refreshStatus()
                if model.canRunCommands { await model.refreshPlayerLists() }
            }
        }
        #if DEBUG
        // 验收钩子：合成鼠标事件到不了这个次级窗口的 SwiftUI 控件，用参数直接落到指定状态。
        // `--players-tab whitelist|banned`、`--selfhosted-settings`。
        .task {
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "--players-tab"), index + 1 < args.count {
                switch args[index + 1] {
                case "whitelist": playerListTab = .whitelist
                case "banned": playerListTab = .banned
                default: playerListTab = .online
                }
            }
            if args.contains("--selfhosted-settings")
                || ProcessInfo.processInfo.environment["ORZMC_DEMO_SETTINGS"] == "1" {
                editing = profile
            }
        }
        #endif
    }

    // MARK: - 内容

    private func content(_ profile: SelfHostedServerProfile) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
                if profile.isConfigured {
                    statusCard(profile)
                    if let error = model.currentStatusError { errorCard(error) }
                    // 玩家卡**始终显示**：没开 RCON 时用 SLP 的 sample 显示"谁在线"（只读），
                    // 否则一个只配了地址的服务器页面会只剩一张状态卡、下面大片空白（真机验收发现）。
                    playersCard(profile)
                    if profile.rconEnabled {
                        consoleCard
                    } else {
                        rconHintCard(profile)
                    }
                } else {
                    setupCard(profile)
                }
            }
            .padding(OrzMCTheme.Spacing.lg)
            .containerRelativeFrame(.horizontal) { width, _ in min(width, 780) }
            .frame(maxWidth: .infinity)
        }
        #if os(iOS)
        .refreshable {
            await model.refreshStatus()
            if model.canRunCommands { await model.refreshPlayerLists() }
        }
        #endif
    }

    // MARK: - 状态卡

    private func statusCard(_ profile: SelfHostedServerProfile) -> some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                Text(profile.displayName)
                    .font(.headline)
                    .lineLimit(1)
                OrzMCStatusBadge(verbatim: statusText, style: statusStyle)
                Spacer(minLength: 0)
                // 加载指示器**常驻占位**（只改透明度）：以前是条件插入，一出现就把卡片撑高、
                // 刷新时整块内容上下抖（真机反馈）。
                ProgressView()
                    .controlSize(.small)
                    .opacity(model.isProbing ? 1 : 0)
                    .frame(width: 16, height: 16)
                    .accessibilityHidden(!model.isProbing)
            }

            Text(profile.address)
                .font(OrzMCTheme.Typography.code)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: OrzMCTheme.Spacing.xs) {
                if let version = model.currentStatus?.versionName {
                    OrzMCTag(version)
                }
                if let players = model.playersText {
                    OrzMCTag(players)
                }
                if let latency = model.currentStatus?.latencyMilliseconds, latency > 0 {
                    OrzMCTag(String(localized: "\(latency) ms"))
                }
                Spacer(minLength: 0)
            }

            if let motd = model.currentStatus?.motd, !motd.isEmpty {
                Text(verbatim: motd)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // 同理：这一行始终存在（没有更新时间就显示占位），否则首次加载完成后卡片会突然长高一行。
            Text(model.currentLastUpdatedAt.map {
                String(localized: "Updated \($0.formatted(date: .omitted, time: .standard))")
            } ?? " ")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(height: 14, alignment: .leading)
        }
        .padding(OrzMCTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: OrzMCTheme.Radius.lg, style: .continuous)
            shape
                .fill(OrzMCTheme.Palette.panelFill)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                OrzMCTheme.Palette.accent.opacity(0.10),
                                OrzMCTheme.Palette.accent.opacity(0.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape.strokeBorder(OrzMCTheme.Palette.accent.opacity(0.22), lineWidth: 1)
                }
        }
    }

    private var statusText: String {
        if model.isProbing, model.currentStatus == nil { return String(localized: "Checking…") }
        guard model.currentStatus != nil else { return String(localized: "Offline") }
        return String(localized: "Online")
    }

    private var statusStyle: OrzMCStatusStyle {
        if model.isProbing, model.currentStatus == nil { return .busy }
        return model.currentStatus != nil ? .running : .idle
    }

    private func errorCard(_ message: String) -> some View {
        OrzMCBanner(verbatim: message, role: .warning)
    }

    // MARK: - 玩家

    /// 玩家卡：**在线 / 白名单 / 封禁** 三份名单，每行直接给对应动作。
    ///
    /// 名单来自 RCON（`list` / `whitelist list` / `banlist`），不是 SLP 的 sample：
    /// sample 常常被服务端隐藏，而且拿不到白名单和封禁。
    private func playersCard(_ profile: SelfHostedServerProfile) -> some View {
        let canRunCommands = model.canRunCommands
        let actionsEnabled = canRunCommands && !model.isSending
        return VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            HStack(spacing: OrzMCTheme.Spacing.sm) {
                Label("Players", systemImage: "person.2")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                ProgressView()
                    .controlSize(.small)
                    .opacity(model.isFetchingLists ? 1 : 0)
                    .frame(width: 16, height: 16)
                Button {
                    Task { await model.refreshPlayerLists() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .disabled(model.isFetchingLists || !canRunCommands)
                .help("Reload online / whitelist / ban lists")
            }

            if profile.rconEnabled {
                Picker("", selection: $playerListTab) {
                    Text("Online (\(model.currentOnlinePlayers.count))").tag(PlayerListTab.online)
                    Text("Whitelist (\(model.currentLists.whitelisted.count))").tag(PlayerListTab.whitelist)
                    Text("Banned (\(model.currentLists.banned.count))").tag(PlayerListTab.banned)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            LazyVStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
                switch playerListTab {
                case .online:
                    if model.currentOnlinePlayers.isEmpty {
                        emptyRow(String(localized: "Nobody is online right now."))
                    }
                    ForEach(model.currentOnlinePlayers, id: \.self) { name in
                        playerRow(name) {
                            if canRunCommands {
                                action("Kick", enabled: actionsEnabled) { await model.performPlayerAction("kick \(name)") }
                                action("Grant OP", enabled: actionsEnabled) { await model.performPlayerAction("op \(name)") }
                                action("Ban", enabled: actionsEnabled) { await model.performPlayerAction("ban \(name)") }
                            }
                        }
                    }
                case .whitelist:
                    if model.currentLists.whitelisted.isEmpty {
                        emptyRow(String(localized: "The whitelist is empty."))
                    }
                    ForEach(model.currentLists.whitelisted, id: \.self) { name in
                        playerRow(name) {
                            action("Remove from Whitelist", enabled: actionsEnabled) { await model.performPlayerAction("whitelist remove \(name)") }
                            action("Grant OP", enabled: actionsEnabled) { await model.performPlayerAction("op \(name)") }
                        }
                    }
                case .banned:
                    if model.currentLists.banned.isEmpty {
                        emptyRow(String(localized: "Nobody is banned."))
                    }
                    ForEach(model.currentLists.banned, id: \.name) { entry in
                        playerRow(entry.name, subtitle: entry.reason) {
                            action("Unban", enabled: actionsEnabled) { await model.performPlayerAction("pardon \(entry.name)") }
                        }
                    }
                }
            }
            .id(playerListTab)

            if profile.rconEnabled {
                HStack(spacing: OrzMCTheme.Spacing.sm) {
                    TextField("", text: $playerNameDraft, prompt: Text("Player name"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit { addToList() }
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.done)
                    #endif
                    Button(addButtonTitle) { addToList() }
                        .disabled(playerNameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let error = model.currentListError {
                Text(verbatim: error)
                    .font(.caption)
                    .foregroundStyle(OrzMCTheme.Palette.danger)
            } else if !profile.rconEnabled {
                HStack(spacing: OrzMCTheme.Spacing.sm) {
                    Text("Turn on RCON to kick players or edit the whitelist.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button("Set Up RCON") { editing = profile }
                        .font(.caption)
                }
            } else if !canRunCommands {
                Text("RCON needs a password. Add it in Settings to manage players.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(OrzMCTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orzMCPanel()
    }

    /// 一行玩家：名字（`subtitle` 有值时为两行，第二行是封禁原因等次要信息）。
    ///
    /// 封禁原因经常是一整句甚至带中文逗号/冒号的长文本（实测真实服务器：
    /// "176.65.148.132 was banned by Console: 你已被此服务器封禁！"），
    /// 之前把它拼进标题里，整行就变成"一段话"。现在名字一行、原因一行并截断。
    private func playerRow(
        _ title: String,
        subtitle: String? = nil,
        @ViewBuilder actions: () -> some View
    ) -> some View {
        HStack(alignment: subtitle == nil ? .center : .top, spacing: OrzMCTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: title)
                    .font(OrzMCTheme.Typography.code)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let subtitle, !subtitle.isEmpty {
                    Text(verbatim: subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                }
            }
            Spacer(minLength: OrzMCTheme.Spacing.sm)
            actions()
        }
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.tertiary)
    }

    /// 注意参数类型必须是 `LocalizedStringKey`：`Button("Kick")` 传 String 字面量会走
    /// `StringProtocol` 那个重载，**不会本地化**——之前中文界面里显示英文 Kick/OP/Ban 就是这个原因。
    private func action(_ title: LocalizedStringKey, enabled: Bool, perform: @escaping () async -> Void) -> some View {
        Button(title) { Task { await perform() } }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!enabled)
    }

    private func addToList() {
        let name = playerNameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let command = switch playerListTab {
        case .online: "whitelist add \(name)"
        case .whitelist: "whitelist add \(name)"
        case .banned: "ban \(name)"
        }
        playerNameDraft = ""
        Task { await model.performPlayerAction(command) }
    }

    private var addButtonTitle: String {
        switch playerListTab {
        case .online, .whitelist: return String(localized: "Add to Whitelist")
        case .banned: return String(localized: "Ban")
        }
    }

    /// 没开启 RCON 时的提示卡（替代整块空白）。
    private func rconHintCard(_ profile: SelfHostedServerProfile) -> some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            Label("Console (RCON)", systemImage: "terminal")
                .font(.subheadline.weight(.semibold))
            Text("Turn on RCON in the server settings to run console commands from here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Set Up RCON") { editing = profile }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(OrzMCTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orzMCPanel()
    }

    // MARK: - 控制台

    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            HStack {
                Label("Console (RCON)", systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                commandPresetMenu
                Button("Clear") { model.clearConsole() }
                    .font(.caption)
                    .disabled(model.currentConsoleLines.isEmpty)
            }

            OrzMCConsoleControls(search: $consoleSearch)
            consoleLog

            HStack(spacing: OrzMCTheme.Spacing.sm) {
                TextField("", text: $model.commandDraft, prompt: Text("Say something or run a command"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .focused($commandFocused)
                    .accessibilityIdentifier("selfHosted.consoleInput")
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.send)
                    #endif
                    .onSubmit { send() }

                Button("Send") { send() }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("selfHosted.consoleSend")
                    .disabled(model.isSending || model.commandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !model.canRunCommands {
                Text("RCON needs a password. Add it in Settings to send commands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(OrzMCTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orzMCPanel()
    }

    /// 常用命令：**需要参数的先填好开头**（`kick `），不需要参数的直接发。
    /// 比"记住 RCON 命令语法"友好，也不会替用户猜参数。
    private var commandPresetMenu: some View {
        Menu {
            Button("List players") { send("list") }
            Button("Save the world") { send("save-all") }
            Divider()
            Button("Say…") { prefill("say ") }
            Button("De-OP…") { prefill("deop ") }
            Divider()
            Button("Whitelist list") { send("whitelist list") }
            Button("Ban list") { send("banlist") }
        } label: {
            Label("Commands", systemImage: "text.badge.plus")
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(model.isSending || !model.canRunCommands)
        .help("Fill in or run a common command")
    }

    private var consoleLog: some View {
        ScrollViewReader { proxy in
            ScrollView(wrapConsoleLines ? .vertical : [.vertical, .horizontal]) {
                OrzMCConsoleRows(filteredConsoleLines, id: \.id, spacing: 2) { line in
                    // ANSI 与 `§` 颜色由共享解析器处理，这里只提供默认颜色。
                    ConsoleLineText(segments: line.segments, fallback: color(for: line.kind))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .id(line.id)
                } empty: {
                    Text(consoleSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                         ? String(localized: "Commands and replies show up here.")
                         : String(localized: "No matching logs", comment: "Console search has no matches"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .fixedSize(horizontal: !wrapConsoleLines, vertical: false)
                .padding(OrzMCTheme.Spacing.xs)
            }
            .frame(minHeight: 140, maxHeight: 220)
            .consoleSurface()
            .consoleMagnification()
            .onChange(of: model.currentConsoleLines.last?.id) {
                guard consoleSearch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                if let last = filteredConsoleLines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: SelfHostedServersModel.ConsoleLine.Kind) -> Color {
        switch kind {
        case .command: return OrzMCTheme.Palette.accent
        case .output: return Color.primary
        case .error: return OrzMCTheme.Palette.danger
        }
    }

    private func send() {
        Task { await model.sendCommand() }
    }

    private func send(_ command: String) {
        Task { await model.sendCommand(command) }
    }

    /// 填进输入框并把焦点放进去：用户补参数后按回车。
    private func prefill(_ prefix: String) {
        model.commandDraft = prefix
        commandFocused = true
    }

    // MARK: - 还没配置

    private func setupCard(_ profile: SelfHostedServerProfile) -> some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            Label("Connect a server you run yourself", systemImage: "server.rack")
                .font(.headline)
            Text("Enter the address and port of a Minecraft server you host (for example one started with `orzmc` in server mode). The app checks its status with Server List Ping; turn on RCON to run console commands.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Server Address…") { editing = profile }
                .buttonStyle(.borderedProminent)
        }
        .padding(OrzMCTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orzMCPanel()
    }
}
