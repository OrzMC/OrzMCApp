//
//  SelfHostedServerView.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCLauncher
import OrzMCProtocol
import SwiftUI

/// 「我的服务器」页：**选服务器 → 看状态 → 发命令**。
///
/// 与远程托管（exaroton）是两条并列的路：
/// - exaroton：账号 + 官方 API + WebSocket；
/// - 自建：直接 Server List Ping 查状态、RCON 发命令，不需要任何第三方账号。
///
/// 同一份代码 macOS / iOS 都能用；macOS 上它和远程托管合并在「服务器」窗口里。
struct SelfHostedServerView: View {
    @State private var model = SelfHostedServersModel()
    /// 正在编辑的服务器档案。**用 `.sheet(item:)` 而不是 `isPresented + 可选值`**：
    /// 后者在"同一帧里既设值又置 true"时会用旧值（nil）构建内容，表现为 sheet 里一片空白
    /// （真机/模拟器都复现到过）。
    @State private var editing: SelfHostedServerProfile?
    @FocusState private var commandFocused: Bool
    @State private var playerListTab: PlayerListTab = .online
    @State private var playerNameDraft = ""

    enum PlayerListTab: Hashable {
        case online
        case whitelist
        case banned
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
                serverPicker

                if let profile = model.selected, profile.isConfigured {
                    statusCard(profile)
                    if let error = model.currentStatusError { errorCard(error) }
                    // 玩家卡**始终显示**：没开 RCON 时用 SLP 的 sample 显示"谁在线"（只读），
                    // 否则一个只配了地址的服务器页面会只剩一张状态卡、下面大片空白（真机验收发现）。
                    playersCard(profile)
                    if profile.rconEnabled {
                        consoleCard
                    } else {
                        rconHintCard
                    }
                } else {
                    setupCard
                }
            }
            .padding(20)
            // iOS 26 的浮动 TabBar 会盖住滚动内容底部（SE 小屏实测：控制台输入行被压住）。
            // `contentMargins` 在这个嵌套结构里不生效，直接在内容尾部留白。
            .padding(.bottom, 76)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(String(localized: "My Server"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshStatus() }
        #endif
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
                editing = model.selected ?? SelfHostedServerProfile()
            }
        }
        #endif
        // 页面可见时每 20s 刷一次当前服务器（比手动点慢得多，够用且省电）。
        .task(id: model.selected?.id) {
            guard model.selected?.isConfigured == true else { return }
            while !Task.isCancelled {
                await model.refreshStatus()
                if model.canRunCommands { await model.refreshPlayerLists() }
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    // MARK: - 选择服务器

    private var serverPicker: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            if model.profiles.servers.isEmpty {
                Text("No server added yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                // 选中态用「勾 + 加粗 + 着色」表达（菜单项没法上背景色）。
                // 试过 `Picker` + `.menu`（系统自己打勾），但 iOS 上它的**触发按钮只显示
                // 选中项的纯文本**：胶囊底色与 `server.rack` 图标都会被丢掉（实测截图），
                // 外观比选中态更重要，所以保留 `Menu` + 自己表达选中。
                // 编辑 / 删除不再放这里：设置里已经有了，重复且容易误触。
                Menu {
                    ForEach(model.profiles.servers) { profile in
                        Button {
                            model.select(profile.id)
                        } label: {
                            if profile.id == model.selected?.id {
                                Label(profile.displayName, systemImage: "checkmark")
                                    .fontWeight(.semibold)
                                    .foregroundStyle(.tint)
                            } else {
                                Text(profile.displayName)
                            }
                        }
                    }
                } label: {
                    Label(model.selected?.displayName ?? String(localized: "Select Server"), systemImage: "server.rack")
                        .font(.callout)
                        // 名字可能很长（"我的-超长-服务器名"）：截断，别把右边按钮挤没了。
                        .lineLimit(1)
                        .truncationMode(.middle)
                        // 点击热区：padding / 背景 / contentShape **放在 label 里**，
                        // 否则胶囊背景画在外面、只有文字区能点（真机反馈"点胶囊空白没反应"）。
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(OrzMCTheme.Palette.controlFill, in: Capsule())
                        .contentShape(Capsule())
                }
                .menuStyle(.borderlessButton)
                .frame(maxWidth: 170, alignment: .leading)
                .accessibilityLabel(Text("Server"))
                .accessibilityIdentifier("selfHosted.serverPicker")
            }

            Spacer(minLength: 0)

            Button {
                Task { await model.refreshStatus() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.selected?.isConfigured != true || model.isProbing)
            .help("Check the server status now")
            .accessibilityIdentifier("selfHosted.refresh")

            Button {
                addServer()
            } label: {
                Label("Add Server", systemImage: "plus")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Add another server")
            .accessibilityIdentifier("selfHosted.addServer")

            Button {
                if let selected = model.selected {
                    edit(selected)
                } else {
                    addServer()
                }
            } label: {
                Label("Settings", systemImage: "slider.horizontal.3")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Server address, port and RCON")
            .accessibilityIdentifier("selfHosted.settings")
        }
    }

    private func addServer() {
        editing = SelfHostedServerProfile()
    }

    private func edit(_ profile: SelfHostedServerProfile) {
        editing = profile
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
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
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
                .disabled(model.isFetchingLists || !model.canRunCommands)
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

            switch playerListTab {
            case .online:
                if model.currentOnlinePlayers.isEmpty {
                    emptyRow(String(localized: "Nobody is online right now."))
                }
                ForEach(model.currentOnlinePlayers, id: \.self) { name in
                    playerRow(name) {
                        if model.canRunCommands {
                            action("Kick") { await model.performPlayerAction("kick \(name)") }
                            action("Grant OP") { await model.performPlayerAction("op \(name)") }
                            action("Ban") { await model.performPlayerAction("ban \(name)") }
                        }
                    }
                }
            case .whitelist:
                if model.currentLists.whitelisted.isEmpty {
                    emptyRow(String(localized: "The whitelist is empty."))
                }
                ForEach(model.currentLists.whitelisted, id: \.self) { name in
                    playerRow(name) {
                        action("Remove from Whitelist") { await model.performPlayerAction("whitelist remove \(name)") }
                        action("Grant OP") { await model.performPlayerAction("op \(name)") }
                    }
                }
            case .banned:
                if model.currentLists.banned.isEmpty {
                    emptyRow(String(localized: "Nobody is banned."))
                }
                ForEach(model.currentLists.banned, id: \.name) { entry in
                    playerRow(entry.name, subtitle: entry.reason) {
                        action("Unban") { await model.performPlayerAction("pardon \(entry.name)") }
                    }
                }
            }

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
                    Button("Set Up RCON") { edit(profile) }
                        .font(.caption)
                }
            } else if !model.canRunCommands {
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
    private func action(_ title: LocalizedStringKey, perform: @escaping () async -> Void) -> some View {
        Button(title) { Task { await perform() } }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!model.canRunCommands || model.isSending)
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
    private var rconHintCard: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            Label("Console (RCON)", systemImage: "terminal")
                .font(.subheadline.weight(.semibold))
            Text("Turn on RCON in the server settings to run console commands from here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let profile = model.selected {
                Button("Set Up RCON") { edit(profile) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if model.currentConsoleLines.isEmpty {
                        Text("Commands and replies show up here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(model.currentConsoleLines) { line in
                        // 与 macOS 本地控制台 / exaroton 控制台同一个渲染组件：
                        // ANSI 与 `§` 颜色由 `ConsoleTextParser` 解析，这里只给"没有颜色码时"兜底色。
                        ConsoleLineText(segments: line.segments, fallback: color(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                }
                .padding(OrzMCTheme.Spacing.xs)
            }
            .frame(minHeight: 140, maxHeight: 220)
            .consoleSurface()
            .onChange(of: model.currentConsoleLines.count) {
                if let last = model.currentConsoleLines.last { proxy.scrollTo(last.id, anchor: .bottom) }
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

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            Label("Connect a server you run yourself", systemImage: "server.rack")
                .font(.headline)
            Text("Enter the address and port of a Minecraft server you host (for example one started with `orzmc` in server mode). The app checks its status with Server List Ping; turn on RCON to run console commands.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Server Address…") { addServer() }
                .buttonStyle(.borderedProminent)
        }
        .padding(OrzMCTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orzMCPanel()
    }
}

#Preview {
    NavigationStack {
        SelfHostedServerView()
    }
}
