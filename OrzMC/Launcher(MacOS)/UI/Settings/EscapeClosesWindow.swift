//
//  EscapeClosesWindow.swift
//  OrzMC
//

import AppKit
import SwiftUI

/// 「**Esc 关掉当前这个窗口**」的统一实现（辅助窗口共用）。
///
/// ## 统一规则（2026-10-23 定稿，写进 `docs/app-ui-design.md`）
///
/// 本应用的窗口分两类：
///
/// | 类别 | 例子 | 关闭方式 |
/// |---|---|---|
/// | **主窗口**（有内容、有导航栈） | 启动器主页 | ⌘W / 红点。**Esc 不关**——它会和"取消搜索/退出编辑"打架 |
/// | **辅助窗口**（浮在上面的工具面） | 设置、控制台、远程服务器 | Esc **和** ⌘W / 红点都能关 |
///
/// 理由：辅助窗口是"临时看一眼 / 操作一下就走"的覆盖层，Esc 是 macOS 里"撤掉这一层"的通用手势
/// （弹窗、面板都是）；而主窗口关掉等于退出应用，不该和一次误按 Esc 绑在一起。
///
/// ## 放行条件（任何一条成立就不处理，把事件交还给系统）
/// - 输入法正在拼写：Esc 是**取消候选**，必须先给输入法；
/// - 窗口上有 sheet/确认框：Esc 应该先关那一层（`hasSheet`）；
/// - 正在文本编辑且 `closeWhileEditingText == false`：Esc 先取消编辑（按住再按一次才关窗）；
/// - 这个窗口不是 key window：Esc 属于当前聚焦的窗口，不能跨窗口抢。
///
/// ## 为什么不用 `.onExitCommand`
/// 辅助窗口的第一响应者常常为空（我们主动清了焦点），Esc 不进 SwiftUI 的命令链，实测无效。
/// 也不要用 `Button().keyboardShortcut(.escape)`：零尺寸按钮在独立 `Window` 里不参与键盘分发。
struct EscapeClosesWindow: ViewModifier {
    /// 本窗口正在输入文本时，Esc 是否也直接关窗（控制台窗口为 `true`：那里的输入框是用来"随手打命令"的）。
    var closeWhileEditingText: Bool
    /// 本窗口**不是** key window 时是否也响应。
    ///
    /// 只有控制台窗口打开这种场景需要：`openWindow(value:)` 之后 key 有时仍留在主窗口
    /// （实测 `isKey=false`），不放宽的话用户按 Esc 毫无反应（#45 修过）。
    /// 放宽时仍然遵守"主窗口正在输入文本就不抢"这条，避免在搜索框里按 Esc 把控制台关掉。
    var allowWhenNotKey: Bool

    @State private var window: NSWindow?
    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .background(WindowReader { window = $0 })
            .onAppear { install() }
            .onDisappear { remove() }
    }

    private func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window, window.isVisible else { return event }
            // 只管聚焦的那个窗口：别让在 A 窗口按的 Esc 把 B 窗口关掉。
            if NSApp.keyWindow !== window {
                guard allowWhenNotKey, !ShortcutEvents.isEditingText else { return event }
            }
            guard !ShortcutEvents.hasSheet, !ShortcutEvents.isComposing else { return event }
            if !closeWhileEditingText, ShortcutEvents.isEditingText { return event }
            guard event.keyCode == 53, ShortcutEvents.modifiers(of: event).isEmpty else { return event }

            close(window)
            return nil
        }
    }

    private func remove() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// `performClose:` 更"正规"（会走 `windowShouldClose`），但 SwiftUI 场景窗口对它不总买账
    /// （设置窗口实测无反应）→ 兜底 `orderOut`，用户看到的就是关掉了。
    private func close(_ window: NSWindow) {
        window.performClose(nil)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            if window.isVisible { window.orderOut(nil) }
        }
    }
}

extension View {
    /// 让这个窗口支持 Esc 关闭（见 `EscapeClosesWindow` 的规则）。
    func escapeClosesWindow(
        closeWhileEditingText: Bool = false,
        allowWhenNotKey: Bool = false
    ) -> some View {
        modifier(
            EscapeClosesWindow(
                closeWhileEditingText: closeWhileEditingText,
                allowWhenNotKey: allowWhenNotKey
            )
        )
    }
}
