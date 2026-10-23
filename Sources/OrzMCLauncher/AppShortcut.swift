import Foundation

/// 应用内**所有可控快捷键**的登记表。
///
/// 为什么集中登记：快捷键散落在 `Commands`、按钮、窗口里时，用户改不了，
/// 开发者也不知道总共有哪些。这里一处声明（默认值 + 文案 + 是否可改），
/// 设置页「快捷键」直接渲染这张表，`ShortcutStore` 负责持久化覆盖值。
///
/// 平台无关：只描述「按键 + 修饰键」，映射到 SwiftUI `KeyEquivalent` 在 app 层做。
public enum AppShortcut: String, CaseIterable, Identifiable, Sendable {
    /// 启动当前目标（客户端/服务端，取决于启动卡）。
    case start
    /// 控制台窗口返回详情页。
    case consoleBack
    /// 切换启动目标（客户端 Vanilla/Fabric → 服务端四个核心，循环）。
    case cycleTarget
    /// 聚焦侧边栏的版本筛选框。
    case focusSearch
    /// 版本列表：跳到最新。
    case jumpNewest
    /// 版本列表：跳到最旧。
    case jumpOldest
    /// 停止全部服务器。
    case stopAll

    public var id: String { rawValue }

    /// 分组标题（设置页分节用）。
    public var group: Group {
        switch self {
        case .start, .consoleBack, .cycleTarget: return .launch
        case .jumpNewest, .jumpOldest, .focusSearch: return .navigation
        case .stopAll: return .lifecycle
        }
    }

    public enum Group: String, CaseIterable, Sendable {
        case launch
        case navigation
        case lifecycle
    }

    /// 默认组合。
    public var defaultSpec: ShortcutSpec {
        switch self {
        case .start: return ShortcutSpec(key: "\r", modifiers: [.command])
        case .consoleBack: return ShortcutSpec(key: "\u{F702}", modifiers: [.command])   // ←
        case .cycleTarget: return ShortcutSpec(key: "t", modifiers: [.command])
        case .focusSearch: return ShortcutSpec(key: "f", modifiers: [.command])
        case .jumpNewest: return ShortcutSpec(key: "\u{F700}", modifiers: [.command])   // ↑
        case .jumpOldest: return ShortcutSpec(key: "\u{F701}", modifiers: [.command])   // ↓
        case .stopAll: return ShortcutSpec(key: "k", modifiers: [.command, .shift])
        }
    }

    /// 展示文案（设置页行标题）；按语言取。
    public var title: String {
        switch self {
        case .start: return String(localized: "Start current target")
        case .consoleBack: return String(localized: "Console: back to detail")
        case .cycleTarget: return String(localized: "Switch launch target")
        case .focusSearch: return String(localized: "Focus version search")
        case .jumpNewest: return String(localized: "Version list: jump to newest")
        case .jumpOldest: return String(localized: "Version list: jump to oldest")
        case .stopAll: return String(localized: "Stop all servers")
        }
    }
}

/// 一个快捷键组合（与 UI 框架无关的表示）。
///
/// `key` 存的是**字符串形式**：普通字符就是它本身（`"k"`），
/// 特殊键用 NSEvent 的函数键码（`"\u{F700}"` = ↑），与 `KeyEquivalent` 的字符一致，
/// 这样映射时不需要额外查表。
public struct ShortcutSpec: Equatable, Sendable {
    public enum Modifier: String, CaseIterable, Sendable {
        case command
        case shift
        case option
        case control
    }

    public var key: String
    public var modifiers: Set<Modifier>

    public init(key: String, modifiers: Set<Modifier>) {
        self.key = key
        self.modifiers = modifiers
    }

    /// 持久化形式：`command+shift+k` / `command+\u{F700}`。
    public var serialized: String {
        let mods = Modifier.allCases.filter { modifiers.contains($0) }.map(\.rawValue)
        return (mods + [key]).joined(separator: "+")
    }

    /// 从持久化形式还原；格式不对返回 `nil`（调用方回退默认值）。
    public init?(serialized: String) {
        var parts = serialized.components(separatedBy: "+")
        guard let last = parts.last, !last.isEmpty else { return nil }
        parts.removeLast()
        var mods = Set<Modifier>()
        for part in parts {
            guard let modifier = Modifier(rawValue: part) else { return nil }
            mods.insert(modifier)
        }
        // 至少要有一个修饰键，否则会抢走普通输入。
        guard !mods.isEmpty else { return nil }
        self.key = last
        self.modifiers = mods
    }

    /// 展示用（`⌘⇧K` / `⌘↩`）。
    public var displayText: String {
        let order: [Modifier] = [.control, .option, .shift, .command]
        var text = order.filter { modifiers.contains($0) }.map { modifier in
            switch modifier {
            case .control: return "⌃"
            case .option: return "⌥"
            case .shift: return "⇧"
            case .command: return "⌘"
            }
        }.joined()
        text += Self.symbol(for: key)
        return text
    }

    /// 功能键的虚拟键码（`NSEvent.keyCode`）。
    ///
    /// 为什么需要：合成事件（以及某些输入法）里方向键的 `charactersIgnoringModifiers`
    /// 可能为空，只按字符匹配会漏；键码是稳定的。
    public var functionKeyCode: UInt16? {
        switch key {
        case "\u{F700}": return 126   // ↑
        case "\u{F701}": return 125   // ↓
        case "\u{F702}": return 123   // ←
        case "\u{F703}": return 124   // →
        case "\r": return 36          // Return
        case "\u{7F}": return 51      // Delete
        case "\u{1B}": return 53      // Esc
        case "\t": return 48          // Tab
        case " ": return 49            // Space
        default: return nil
        }
    }

    /// 事件是否匹配本组合（字符或键码二选一，修饰键必须完全一致）。
    public func matches(keyCode: UInt16, characters: String?, modifiers: Set<Modifier>) -> Bool {
        guard self.modifiers == modifiers else { return false }
        if let functionKeyCode { return keyCode == functionKeyCode }
        guard let characters, let first = characters.first, let wanted = key.first else { return false }
        return String(first).lowercased() == String(wanted).lowercased()
    }

    /// `key` → 可读符号（功能键给符号，普通字符给大写）。
    public static func symbol(for key: String) -> String {
        switch key {
        case "\r": return "↩"
        case "\u{F700}": return "↑"
        case "\u{F701}": return "↓"
        case "\u{F702}": return "←"
        case "\u{F703}": return "→"
        case "\u{7F}": return "⌫"
        case "\u{1B}": return "⎋"
        case "\t": return "⇥"
        case " ": return "Space"
        default: return key.uppercased()
        }
    }
}
