//
//  VersionListKeyboardNavigation.swift
//  OrzMC
//

import AppKit
import SwiftUI

/// 版本列表的键盘导航（仅 macOS）：`↑/↓` 切换版本，`⌘↑/⌘↓` 跳到最新/最旧。
///
/// 为什么不用 `.onKeyPress`：侧边栏的 `List` 不总能拿到键盘焦点，
/// `onKeyPress` 只在它自己聚焦时才触发，所以在详情区/搜索框上按时"快捷键不生效"。
/// 这里装一个 **应用内本地事件监听**（`NSEvent.addLocalMonitorForEvents`），
/// 只要主窗口在，快捷键就作用于版本列表。
///
/// 关键约束（维护者要求）：**不影响搜索框**——正在编辑文本时（第一响应者是 `NSTextView`
/// 字段编辑器）直接放行，方向键留给光标移动。
struct VersionListKeyboardNavigation: ViewModifier {
    /// `(delta, jumpToEdge)`：±1 走一格；`jumpToEdge` 为真时跳首/末。
    let onStep: (Int, Bool) -> Void

    @State private var monitor: Any?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: install)
            .onDisappear(perform: remove)
    }

    private static func debugLog(_ message: String) {
        guard ProcessInfo.processInfo.environment["ORZMC_KEY_DEBUG"] != nil else { return }
        let stamp = String(format: "%.3f", ProcessInfo.processInfo.systemUptime)
        FileHandle.standardError.write(Data("key[\(stamp)]: \(message)\n".utf8))
    }

    private func install() {
        guard monitor == nil else { return }
        Self.debugLog("monitor installed")
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 只有**多行编辑器**（TextEditor）才让开方向键；单行输入框（搜索框、用户名…）
            // 里按 ↑/↓ 本来就是无用操作，交给列表导航更符合 Finder / Xcode 的习惯，
            // 而且我们 consume 事件，输入内容与光标都不受影响。
            // 输入法正在拼写：候选词也用方向键，绝不能拦。
            if ShortcutEvents.isComposing {
                Self.debugLog("skip: IME composing")
                return event
            }
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, !editor.isFieldEditor {
                Self.debugLog("skip: multi-line editor (keyCode \(event.keyCode))")
                return event
            }
            // 有 sheet（确认框、令牌输入…）时放行，别和弹层抢方向键。
            guard !ShortcutEvents.hasSheet else {
                Self.debugLog("skip: sheet up")
                return event
            }

            let jumpToEdge = event.modifierFlags.contains(.command)
            switch event.keyCode {
            case 126:                       // ↑
                onStep(-1, jumpToEdge)
                if ProcessInfo.processInfo.environment["ORZMC_KEY_DEBUG"] != nil {
                    FileHandle.standardError.write(Data("key: handled up (jump=\(jumpToEdge))\n".utf8))
                }
                return nil
            case 125:                       // ↓
                onStep(1, jumpToEdge)
                if ProcessInfo.processInfo.environment["ORZMC_KEY_DEBUG"] != nil {
                    FileHandle.standardError.write(Data("key: handled down (jump=\(jumpToEdge))\n".utf8))
                }
                return nil
            default:
                return event
            }
        }
    }

    private func remove() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}

extension View {
    /// 给版本列表装键盘导航（↑/↓ 走一格，⌘↑/⌘↓ 跳首末）。
    func versionListKeyboardNavigation(_ onStep: @escaping (Int, Bool) -> Void) -> some View {
        modifier(VersionListKeyboardNavigation(onStep: onStep))
    }
}
