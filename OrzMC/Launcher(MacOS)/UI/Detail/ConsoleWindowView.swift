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
        // ⌘←：从控制台回详情页。
        //
        // 为什么不用 `.keyboardShortcut`：这个视图是**独立 Window** 的根，零尺寸按钮
        // 不参与键盘分发（实测完全不触发）。改为本地事件监听 + 关闭当前窗口。
        .background(WindowReader { window = $0 })
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }
}

// MARK: - ⌘← 返回

private extension ConsoleWindowView {
    /// 匹配当前生效的 `consoleBack` 组合（可在设置里改）。
    func matchesBackShortcut(_ event: NSEvent) -> Bool {
        let spec = shortcuts.spec(for: .consoleBack)
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var mods: Set<ShortcutSpec.Modifier> = []
        if flags.contains(.command) { mods.insert(.command) }
        if flags.contains(.shift) { mods.insert(.shift) }
        if flags.contains(.option) { mods.insert(.option) }
        if flags.contains(.control) { mods.insert(.control) }
        return spec.matches(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            modifiers: mods
        )
    }

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 只要**这个控制台窗口还开着**就响应。
            // 不能要求它是 key window：`openWindow(value:)` 打开后 key 仍可能留在主窗口，
            // 那样 ⌘← 永远不生效（实测）。主窗口里按 ⌘← 顺带关掉控制台也符合预期。
            guard let window, window.isVisible else { return event }
            guard matchesBackShortcut(event) else { return event }
            window.performClose(nil)
            return nil
        }
    }

    func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// 读到自己所在的 `NSWindow`（用于"只在这个窗口是 key 时响应快捷键"）。
private struct WindowReader: NSViewRepresentable {
    let onChange: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onChange(view.window) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { onChange(nsView.window) }
    }
}
