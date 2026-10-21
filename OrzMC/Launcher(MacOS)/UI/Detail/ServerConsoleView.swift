//
//  ServerConsoleView.swift
//  OrzMC
//

import AppKit
import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI
import UniformTypeIdentifiers

/// 控制台：滚动日志 +（服务端）命令输入，支持上/下方向键翻历史。
///
/// - **服务端**：命令输入 + 顶部四个生命周期按钮（启动 / 重启 / 停止 / 终止），
///   在控制台里就能管，不必退回详情页；
/// - **客户端**：**只读**日志（Minecraft 客户端不接受控制台命令），底部明确说明。
///
/// 日志由 `ServerConsoleModel` 处理干净（去 ANSI、按行切、限 2000 行），这里只渲染。
struct ServerConsoleView: View {
    /// 控制台属于**这个实例**（版本 + 客户端/某个服务端核心）——实例之间完全独立。
    let title: String
    /// 由 `AppModel` 按实例取好的模型（客户端与服务端走同一套）。
    let console: ServerConsoleModel
    /// 实例身份（`versionId` + `software`）；`software == nil` 即客户端 → 只读。
    let target: ConsoleTarget?

    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    @State private var command = ""
    @State private var historyOffset: Int?
    /// 是否跟随最新日志。用户向上翻日志时关掉，不会被新行“拽”回底部。
    @State private var followOutput = true
    /// 日志过滤（不区分大小写的子串匹配）。
    @State private var searchText = ""
    @State private var pendingRisky: RiskyAction?
    @FocusState private var inputFocused: Bool

    private var software: SettingsModel.ServerSoftware? { target?.software }
    private var versionId: String { target?.versionId ?? "" }

    private var filteredLines: [ConsoleLine] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return console.lines }
        return console.lines.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }
    /// 客户端不支持命令输入，只给日志。
    private var supportsCommands: Bool { software != nil }
    private var availability: InstanceActionAvailability? {
        guard let software else { return nil }
        return app.availability(versionId: versionId, software: software)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logList
            Divider()
            inputRow
        }
        .navigationTitle("Console — \(title)")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search log")
        .toolbar {
            if let software, let availability {
                ToolbarItemGroup {
                    Button {
                        app.control(.start, versionId: versionId, software: software)
                    } label: {
                        Label("Start", systemImage: "play.circle.fill")
                    }
                    .disabled(!availability.canStart)
                    .help("Start this server")

                    Button {
                        pendingRisky = .restartServer(versionId: versionId, software: software)
                    } label: {
                        Label("Restart", systemImage: "arrow.clockwise.circle")
                    }
                    .disabled(!availability.canRestart)
                    .help("Restart = graceful stop, then start again")

                    Button {
                        pendingRisky = .stopServer(versionId: versionId, software: software)
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .disabled(!availability.canStop)
                    .help("Send `stop` so the server saves and exits normally")

                    Button {
                        pendingRisky = .terminateServer(versionId: versionId, software: software)
                    } label: {
                        Label("Terminate", systemImage: "xmark.octagon")
                    }
                    .disabled(!availability.canTerminate)
                    .help("Kill the process now (may lose unsaved world data)")
                }
            }
            ToolbarItemGroup {
                if let target {
                    Button("Open in New Window", systemImage: "macwindow.badge.plus") {
                        openWindow(value: target)
                    }
                    .help("Open this console in its own window")
                }

                Button("Export Log…", systemImage: "square.and.arrow.down") {
                    exportLog()
                }
                .help("Save the full log to a .log/.txt file")

                Button("Clear") { console.clear() }
                    .help("Clear the visible log (does not affect the server)")
            }
        }
        .alert(
            pendingRisky?.confirmTitle ?? "",
            isPresented: Binding(
                get: { pendingRisky != nil },
                set: { if !$0 { pendingRisky = nil } }
            ),
            presenting: pendingRisky
        ) { action in
            Button(action.confirmButtonTitle, role: action.isDestructive ? .destructive : nil) {
                perform(action)
            }
            Button("Cancel", role: .cancel) { pendingRisky = nil }
        } message: { action in
            Text(action.message(selectedVersionId: versionId))
        }
    }

    private var header: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            OrzMCStatusBadge(
                statusKey,
                style: console.isAttached ? .running : .idle
            )

            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let software, let status = statusOverride(software: software) {
                OrzMCTag(status, tint: OrzMCTheme.Palette.warning)
            }

            Spacer()

            Toggle("Follow", isOn: $followOutput)
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Scroll to the newest line as output arrives")

            Group {
                if searchText.isEmpty {
                    Text("\(console.lines.count) lines")
                } else {
                    Text("\(filteredLines.count) / \(console.lines.count) lines")
                }
            }
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, OrzMCTheme.Spacing.md)
        .padding(.vertical, OrzMCTheme.Spacing.sm)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filteredLines) { line in
                        Text(line.text)
                            .font(OrzMCTheme.Typography.console)
                            .foregroundStyle(line.isCommand ? AnyShapeStyle(OrzMCTheme.Palette.accent) : AnyShapeStyle(.primary))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(OrzMCTheme.Spacing.sm)
                .textSelection(.enabled)
            }
            .consoleSurface()
            .overlay {
                if filteredLines.isEmpty, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search(text: searchText)
                }
            }
            .onChange(of: console.lines.last?.id) {
                guard followOutput, searchText.isEmpty, let last = console.lines.last else { return }
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            .onChange(of: followOutput) {
                guard followOutput, searchText.isEmpty, let last = console.lines.last else { return }
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
        .frame(minHeight: 220)
        .padding(.horizontal, OrzMCTheme.Spacing.md)
        .padding(.vertical, OrzMCTheme.Spacing.sm)
    }

    @ViewBuilder
    private var inputRow: some View {
        if supportsCommands {
            commandInputRow
        } else {
            HStack(spacing: 6) {
                Image(systemName: "eye")
                    .foregroundStyle(.secondary)
                Text("Log only — the Minecraft client does not accept console commands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, OrzMCTheme.Spacing.md)
            .padding(.vertical, OrzMCTheme.Spacing.sm)
        }
    }

    private var commandInputRow: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            Text(">")
                .font(OrzMCTheme.Typography.consoleInput)
                .foregroundStyle(.secondary)
            TextField(
                console.isAttached ? "Type a command (e.g. say hi, op <player>, stop)" : "Server is not running",
                text: $command
            )
            .textFieldStyle(.plain)
            .font(OrzMCTheme.Typography.consoleInput)
            .focused($inputFocused)
            .disabled(!console.isAttached)
            .onSubmit(sendCommand)
            .onKeyPress(.upArrow) { recallHistory(offset: 1) }
            .onKeyPress(.downArrow) { recallHistory(offset: -1) }

            Button("Send", action: sendCommand)
                .disabled(!console.isAttached || command.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, OrzMCTheme.Spacing.md)
        .padding(.vertical, OrzMCTheme.Spacing.sm)
        .onAppear { inputFocused = console.isAttached }
    }

    /// "启动中/停止中…"这类进行态（服务端自己维护的生命周期活动）。
    private var statusKey: LocalizedStringKey {
        if console.isAttached {
            return supportsCommands ? "Running" : "Game running"
        }
        return supportsCommands ? "Stopped" : "Game not running"
    }

    private func statusOverride(software: SettingsModel.ServerSoftware) -> String? {
        app.activity(versionId: versionId, software: software).localizedStatusText
    }

    private func perform(_ action: RiskyAction) {
        pendingRisky = nil
        switch action {
        case let .stopServer(versionId, software):
            app.control(.stop, versionId: versionId, software: software)
        case let .restartServer(versionId, software):
            app.control(.restart, versionId: versionId, software: software)
        case let .terminateServer(versionId, software):
            app.control(.terminate, versionId: versionId, software: software)
        default:
            break
        }
    }

    private func sendCommand() {
        guard console.send(command) else { return }
        command = ""
        historyOffset = nil
    }

    /// 导出完整日志（不受搜索过滤影响）。用系统保存面板，路径与覆盖确认交给系统。
    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "\(title).log"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let text = console.lines.map(\.text).joined(separator: "\n")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            app.error = LauncherError(
                code: "E_IO",
                message: "Could not write the log: \(error.localizedDescription)"
            )
        }
    }

    /// ↑/↓ 翻历史：`historyOffset` 从 0（最近一条）开始递增。
    private func recallHistory(offset delta: Int) -> KeyPress.Result {
        let next = (historyOffset ?? -1) + delta
        if let entry = console.historyEntry(at: next) {
            historyOffset = next
            command = entry
        } else if next < 0 {
            historyOffset = nil
            command = ""
        }
        return .handled
    }
}

#Preview {
    NavigationStack {
        ServerConsoleView(
            title: "1.21.5 Paper",
            console: ServerConsoleModel(),
            target: ConsoleTarget(versionId: "1.21.5", software: .paper)
        )
    }
    .frame(width: 720, height: 480)
    .environment(AppModel())
}


/// 独立控制台窗口的内容。
///
/// 共享主窗口的 `AppModel`（因此 `ServerConsoleModel` 是同一份），
/// 只是换一个窗口展示；`WindowGroup(for: ConsoleTarget.self)` 由 `openWindow(value:)` 打开。
struct ConsoleWindowView: View {
    @Environment(AppModel.self) private var app
    let target: ConsoleTarget

    var body: some View {
        NavigationStack {
            ServerConsoleView(
                title: target.title,
                console: app.console(for: target),
                target: target
            )
        }
        .frame(minWidth: 720, minHeight: 420)
    }
}
