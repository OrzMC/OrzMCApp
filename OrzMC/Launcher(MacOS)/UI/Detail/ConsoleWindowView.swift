//
//  ConsoleWindowView.swift
//  OrzMC
//

import AppKit
import OrzMCLauncher
import SwiftUI

/// 独立控制台窗口的内容。
///
/// 共享主窗口的 `AppModel`（因此 `ServerConsoleModel` 是同一份），
/// 只是换一个窗口展示；`WindowGroup(for: ConsoleTarget.self)` 由 `openWindow(value:)` 打开。
struct ConsoleWindowView: View {
    @Environment(AppModel.self) private var app
    @Environment(ShortcutStore.self) private var shortcuts
    let target: ConsoleTarget

    @State private var window: NSWindow?

    var body: some View {
        NavigationStack {
            ServerConsoleView(
                title: target.title,
                console: app.console(for: target),
                target: target
            )
        }
        .frame(minWidth: 720, minHeight: 420)
        // Esc：关闭这个独立控制台窗口（⌘← 留给"详情页内导航 → 控制台页"的返回场景）。
        .background(WindowReader { newWindow in
            window = newWindow
            // 打开控制台就把焦点给这个窗口：否则 Esc 这类"本窗口快捷键"不生效，
            // 用户也会觉得"开了但没在用它"。
            if let newWindow, newWindow.isVisible, NSApp.keyWindow !== newWindow {
                newWindow.makeKeyAndOrderFront(nil)
            }
        })
        // 规则见 `EscapeClosesWindow`：控制台里的输入框是用来随手打命令的，
        // 因此正在打字时按 Esc 也直接关窗（与设置窗口相反）。
        .escapeClosesWindow(closeWhileEditingText: true, allowWhenNotKey: true)
    }
}
