//
//  ShortcutEvents.swift
//  OrzMC
//

import AppKit
import OrzMCLauncher

/// 快捷键事件处理的公共判定（输入法、文本编辑、弹层）。
///
/// 为什么要集中：快捷键分布在菜单（AppKit key equivalent）、按钮（`keyboardShortcut`）和
/// 几个 `NSEvent` 本地监听里。监听器**先于**菜单拿到事件，一旦判定写错就会把按键吞掉——
/// 输入法候选、菜单方向键、弹层里的快捷键都会表现成"没反应"。
enum ShortcutEvents {

    /// 输入法正在拼写（有 marked text）：**任何**快捷键都放行，
    /// 否则候选词选择、上屏用的回车/方向键会被我们吃掉。
    static var isComposing: Bool {
        guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return false }
        return editor.hasMarkedText()
    }

    /// 正在文本输入（字段编辑器）。
    static var isEditingText: Bool {
        (NSApp.keyWindow?.firstResponder as? NSTextView)?.isFieldEditor == true
    }

    /// 有弹层（确认框 / sheet）：交给弹层处理。
    static var hasSheet: Bool {
        NSApp.keyWindow?.attachedSheet != nil
    }

    /// 把 `NSEvent.modifierFlags` 转成登记表用的集合。
    static func modifiers(of event: NSEvent) -> Set<ShortcutSpec.Modifier> {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var result: Set<ShortcutSpec.Modifier> = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }

    /// 事件是否匹配某条快捷键（键码/字符二选一，修饰键完全一致）。
    static func matches(_ event: NSEvent, _ spec: ShortcutSpec) -> Bool {
        spec.matches(
            keyCode: event.keyCode,
            characters: event.charactersIgnoringModifiers,
            modifiers: modifiers(of: event)
        )
    }

    /// 带 ⌘ 的组合视为"命令"：正在输入文本时也应当生效（与 macOS 习惯一致）。
    static func isCommand(_ event: NSEvent) -> Bool {
        event.modifierFlags.contains(.command)
    }
}
