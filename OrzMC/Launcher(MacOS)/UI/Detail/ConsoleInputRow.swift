//
//  ConsoleInputRow.swift
//  OrzMC
//

import OrzMCDesignSystem
import SwiftUI

/// 控制台底部输入区。
///
/// - 服务端：命令输入框 + Send（↑/↓ 翻历史）；
/// - 客户端：只读说明（Minecraft 客户端不接受控制台命令）。
struct ConsoleInputRow: View {
    let isAttached: Bool
    let supportsCommands: Bool
    @Binding var command: String
    let onSend: () -> Void
    /// ↑/↓ 翻历史（`+1` 更早，`-1` 更新）。
    let onRecall: (Int) -> KeyPress.Result

    @FocusState private var inputFocused: Bool

    var body: some View {
        if supportsCommands {
            commandInput
        } else {
            readOnlyHint
        }
    }

    private var commandInput: some View {
        // `.plain` 字段没有内边距，且默认 `.center` 会把它和按钮/提示符挤出不同基线：
        // 这里显式居中 + 给提示符固定宽度、给字段最小高度与竖向内边距。
        HStack(alignment: .center, spacing: OrzMCTheme.Spacing.sm) {
            Text(">")
                .font(OrzMCTheme.Typography.consoleInput)
                .foregroundStyle(.secondary)
                .frame(width: 10, alignment: .leading)
                .accessibilityHidden(true)
            TextField(
                isAttached ? "Type a command (e.g. say hi, op <player>, stop)" : "Server is not running",
                text: $command
            )
            .textFieldStyle(.plain)
            .font(OrzMCTheme.Typography.consoleInput)
            .padding(.vertical, 3)
            .frame(minHeight: 20)
            .focused($inputFocused)
            .disabled(!isAttached)
            .onSubmit(onSend)
            .onKeyPress(.upArrow) { onRecall(1) }
            .onKeyPress(.downArrow) { onRecall(-1) }

            Button("Send", action: onSend)
                .controlSize(.regular)
                .disabled(!isAttached || command.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(.horizontal, OrzMCTheme.Spacing.md)
        .padding(.vertical, OrzMCTheme.Spacing.sm)
        .onAppear { inputFocused = isAttached }
    }

    private var readOnlyHint: some View {
        HStack(spacing: 6) {
            Image(systemName: "eye")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Log only — the Minecraft client does not accept console commands.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, OrzMCTheme.Spacing.md)
        .padding(.vertical, OrzMCTheme.Spacing.sm)
    }
}
