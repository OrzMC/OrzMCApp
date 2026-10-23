//
//  ConsoleWindowView.swift
//  OrzMC
//

import OrzMCLauncher
import SwiftUI

/// 独立控制台窗口的内容。
///
/// 共享主窗口的 `AppModel`（因此 `ServerConsoleModel` 是同一份），
/// 只是换一个窗口展示；`WindowGroup(for: ConsoleTarget.self)` 由 `openWindow(value:)` 打开。
struct ConsoleWindowView: View {
    @Environment(AppModel.self) private var app
    @Environment(ShortcutStore.self) private var shortcuts
    @Environment(\.dismiss) private var dismiss
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
        // ⌘←：从控制台回详情页（关闭这个独立窗口，主窗口还在）。
        // 用零尺寸按钮承载快捷键：SwiftUI 里 `keyboardShortcut` 只能挂在可触发控件上。
        .background {
            Button("Back to detail") { dismiss() }
                .keyboardShortcut(shortcuts.spec(for: .consoleBack).keyEquivalent,
                                  modifiers: shortcuts.spec(for: .consoleBack).eventModifiers)
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }
}
