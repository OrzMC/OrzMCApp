//
//  ServerConsoleView.swift
//  OrzMC
//

import OrzMCLauncher
import SwiftUI

/// 服务端控制台：滚动日志 + 命令输入（支持上/下方向键翻历史）。
///
/// 日志由 `ServerConsoleModel` 处理干净（去 ANSI、按行切、限 2000 行），这里只渲染。
struct ServerConsoleView: View {
    /// 控制台属于**这个实例**（版本 + 客户端/某个服务端核心）——实例之间完全独立。
    let title: String
    /// 由 `AppModel` 按实例取好的模型（客户端与服务端走同一套）。
    let console: ServerConsoleModel

    @State private var command = ""
    @State private var historyOffset: Int?
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            logList
            Divider()
            inputRow
        }
        .navigationTitle("Console — \(title)")
        .toolbar {
            ToolbarItem {
                Button("Clear") { console.clear() }
                    .help("Clear the visible log (does not affect the server)")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(console.isAttached ? Color.green : Color.secondary)
                .frame(width: 8, height: 8)
            Text(console.isAttached
                 ? "Running — \(title)"
                 : "Stopped — \(title) (log is kept)")
                .font(.callout)
            Spacer()
            Text("\(console.lines.count) lines")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(console.lines) { line in
                        Text(line.text)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(line.isCommand ? Color.accentColor : Color.primary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(line.id)
                    }
                }
                .padding(8)
            }
            .background(Color.black.opacity(0.06))
            .onChange(of: console.lines.count) {
                if let last = console.lines.last {
                    withAnimation(.linear(duration: 0.1)) {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
        .frame(minHeight: 220)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            Text(">")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
            TextField(
                console.isAttached ? "Type a command (e.g. say hi, op <player>, stop)" : "Server is not running",
                text: $command
            )
            .textFieldStyle(.plain)
            .font(.system(.body, design: .monospaced))
            .focused($inputFocused)
            .disabled(!console.isAttached)
            .onSubmit(sendCommand)
            .onKeyPress(.upArrow) { recallHistory(offset: 1) }
            .onKeyPress(.downArrow) { recallHistory(offset: -1) }

            Button("Send", action: sendCommand)
                .disabled(!console.isAttached || command.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .onAppear { inputFocused = console.isAttached }
    }

    private func sendCommand() {
        guard console.send(command) else { return }
        command = ""
        historyOffset = nil
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
            console: ServerConsoleModel()
        )
    }
    .frame(width: 720, height: 480)
}
