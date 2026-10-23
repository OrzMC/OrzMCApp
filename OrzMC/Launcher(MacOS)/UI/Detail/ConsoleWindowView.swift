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

    @State private var keyMonitor: Any?
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
        //
        // 为什么不用 `.keyboardShortcut`：这个视图是**独立 Window** 的根，零尺寸按钮
        // 不参与键盘分发（实测完全不触发）。改为本地事件监听 + 关闭当前窗口。
        .background(WindowReader { newWindow in
            window = newWindow
            // 打开控制台就把焦点给这个窗口：否则 Esc/⌘← 这类"本窗口快捷键"不生效，
            // 用户也会觉得"开了但没在用它"。
            if let newWindow, newWindow.isVisible, NSApp.keyWindow !== newWindow {
                newWindow.makeKeyAndOrderFront(nil)
            }
        })
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }
}

// MARK: - Esc 关闭

private extension ConsoleWindowView {
    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 不要求这个窗口是 key window：`openWindow(value:)` 打开后 key 常常仍留在主窗口
            //（实测 `isKey=false`），那样 Esc 永远不生效。只要控制台窗口还开着就响应；
            // 正在输入文本时让开（主窗口搜索框的 Esc 仍归它自己）。
            guard let window, window.isVisible else { return event }
            guard !ShortcutEvents.hasSheet, !ShortcutEvents.isComposing else { return event }
            if ShortcutEvents.isEditingText, NSApp.keyWindow !== window { return event }
            // 独立控制台窗口：**Esc** 关闭（用户约定；⌘← 是"详情页内导航"用的，不在这里）。
            guard event.keyCode == 53, ShortcutEvents.modifiers(of: event).isEmpty else { return event }
            window.performClose(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if window.isVisible { window.orderOut(nil) }
            }
            return nil
        }
    }
    func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
