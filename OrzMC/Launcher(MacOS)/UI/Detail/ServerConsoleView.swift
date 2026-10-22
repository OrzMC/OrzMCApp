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
    /// 跟随最新日志的状态机（暂停 / 未读 / 搜索的判定都在这里，见 `ConsoleFollowState`）。
    @State private var follow = ConsoleFollowState()
    /// 显式「回到最新」的滚动请求：等列表按新状态重排后再滚，避免滚到被过滤的旧结果集。
    @State private var scrollToLatestToken = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 日志过滤（不区分大小写的子串匹配）。
    @State private var searchText = ""
    @State private var pendingRisky: RiskyAction?

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

    /// 「回到最新」：退出搜索、恢复跟随，滚到当前最后一行。
    /// 滚动要等这一轮状态生效后再做，所以走一个 token，而不是直接在这里 `scrollTo`。
    private func requestReturnToLatest() {
        follow.requestFollow()
        searchText = ""
        scrollToLatestToken &+= 1
    }

    var body: some View {
        VStack(spacing: 0) {
            ConsoleHeader(
                title: title,
                statusKey: statusKey,
                isAttached: console.isAttached,
                statusTag: software.flatMap { statusOverride(software: $0) },
                totalLines: console.lines.count,
                visibleLines: searchText.isEmpty ? nil : filteredLines.count,
                follow: $follow,
                onRequestFollow: requestReturnToLatest
            )
            Divider()
            logList
            Divider()
            ConsoleInputRow(
                isAttached: console.isAttached,
                supportsCommands: supportsCommands,
                command: $command,
                onSend: sendCommand,
                onRecall: recallHistory
            )
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
            // 低频与破坏性动作收进溢出菜单：生命周期（高频）+ 菜单两项，
            // 960pt 下工具栏不再被 7 个按钮挤爆（HIG：工具栏优先保留当前主动作）。
            ToolbarItem {
                Menu {
                    if let target {
                        Button("Open in New Window", systemImage: "macwindow.badge.plus") {
                            openWindow(value: target)
                        }
                        Divider()
                    }
                    Button("Export Log…", systemImage: "square.and.arrow.down") {
                        exportLog()
                    }
                    Button("Clear", systemImage: "trash") { console.clear() }
                } label: {
                    Label("Console Actions", systemImage: "ellipsis.circle")
                        .labelStyle(.iconOnly)
                }
                .help("Open in a new window, export, or clear the log")
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
                .background(
                    ConsoleScrollObserver(
                        onLeaveBottom: { follow.userLeftBottom() },
                        onReachBottom: { follow.userReachedBottom() }
                    )
                )
            }
            .consoleSurface()
            .overlay {
                if filteredLines.isEmpty, !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    // 无参版本会自动带上搜索词，无需自己传。
                    ContentUnavailableView.search
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if follow.showsReturnToLatest {
                    Button {
                        requestReturnToLatest()
                    } label: {
                        Label("Back to Latest (\(follow.unreadCount))", systemImage: "arrow.down.to.line")
                    }
                    .buttonStyle(.borderedProminent)
                    .help("Clear the search if needed, then follow new output again")
                    .padding(OrzMCTheme.Spacing.sm)
                }
            }
            .onChange(of: console.lines.last?.id) { oldValue, newValue in
                // 日志被清空时不产生未读。
                guard let newValue else { return }
                let appended = max(1, newValue - (oldValue ?? (newValue - 1)))
                follow.appended(appended)
                guard follow.shouldScrollToLatest else { return }
                // 连续输出不做动画；只有用户明确“回到最新”才可选短动画（并尊重减少动态效果）。
                proxy.scrollTo(newValue, anchor: .bottom)
            }
            .onChange(of: scrollToLatestToken) {
                // 搜索框已清空/状态已生效，此时滚动才是对当前行集有效的。
                guard let last = console.lines.last?.id else { return }
                if reduceMotion {
                    proxy.scrollTo(last, anchor: .bottom)
                } else {
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(last, anchor: .bottom)
                    }
                }
                // 刚从搜索结果切回全量日志时 LazyVStack 要重排；布局完再补一次，保证真的落到最新行。
                Task { @MainActor in
                    await Task.yield()
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .onChange(of: searchText) {
                follow.searchChanged(isEmpty: searchText.isEmpty)
            }
            .onAppear {
                if let last = console.lines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
        .frame(minHeight: 220)
        .padding(.horizontal, OrzMCTheme.Spacing.md)
        .padding(.vertical, OrzMCTheme.Spacing.sm)
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
