//
//  ShortcutStore.swift
//  OrzMC
//

import Foundation
import Observation
import OrzMCLauncher
import SwiftUI

/// 快捷键的用户覆盖值（`orzmc.shortcuts.<id>`）。
///
/// 默认值在 `AppShortcut.defaultSpec`（平台无关、可单测）；这里只负责"读写覆盖 + 通知 UI"。
@MainActor
@Observable
final class ShortcutStore {

    private static let prefix = "orzmc.shortcuts."

    private let defaults: UserDefaults
    private var overrides: [String: String] = [:]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        for shortcut in AppShortcut.allCases {
            if let raw = defaults.string(forKey: Self.prefix + shortcut.rawValue) {
                overrides[shortcut.rawValue] = raw
            }
        }
    }

    /// 某条快捷键当前生效的组合。
    func spec(for shortcut: AppShortcut) -> ShortcutSpec {
        if let raw = overrides[shortcut.rawValue], let spec = ShortcutSpec(serialized: raw) {
            return spec
        }
        return shortcut.defaultSpec
    }

    /// 是否被用户改过（设置页用来显示「恢复默认」）。
    func isCustomized(_ shortcut: AppShortcut) -> Bool {
        overrides[shortcut.rawValue] != nil
    }

    func set(_ spec: ShortcutSpec, for shortcut: AppShortcut) {
        overrides[shortcut.rawValue] = spec.serialized
        defaults.set(spec.serialized, forKey: Self.prefix + shortcut.rawValue)
    }

    func reset(_ shortcut: AppShortcut) {
        overrides[shortcut.rawValue] = nil
        defaults.removeObject(forKey: Self.prefix + shortcut.rawValue)
    }

    func resetAll() {
        for shortcut in AppShortcut.allCases { reset(shortcut) }
    }
}

// MARK: - SwiftUI 映射

extension ShortcutSpec {
    var keyEquivalent: KeyEquivalent {
        KeyEquivalent(key.first ?? " ")
    }

    var eventModifiers: EventModifiers {
        var result: EventModifiers = []
        if modifiers.contains(.command) { result.insert(.command) }
        if modifiers.contains(.shift) { result.insert(.shift) }
        if modifiers.contains(.option) { result.insert(.option) }
        if modifiers.contains(.control) { result.insert(.control) }
        return result
    }
}

// MARK: - 录制

/// 从 `NSEvent` 里取出一个 `ShortcutSpec`（必须有修饰键；`Esc` 取消由调用方处理）。
enum ShortcutRecorder {
    static func spec(from event: NSEvent) -> ShortcutSpec? {
        var modifiers: Set<ShortcutSpec.Modifier> = []
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        guard !modifiers.isEmpty else { return nil }

        let chars = event.charactersIgnoringModifiers ?? ""
        guard let key = chars.first else { return nil }
        // 修饰键本身不算按键。
        if key == "\u{1B}" { return nil }
        return ShortcutSpec(key: String(key), modifiers: modifiers)
    }
}
