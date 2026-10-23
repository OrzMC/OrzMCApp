//
//  ShortcutsSettingsView.swift
//  OrzMC
//

import AppKit
import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 设置 →「快捷键」：把应用里**所有**快捷键收录成一张表，可控的那几条可以改。
///
/// 分两类：
/// - **可改**：`AppShortcut` 登记表里的条目（启动、控制台返回、版本跳转、停止全部），
///   覆盖值存 `UserDefaults`，菜单与按钮都读同一份 `ShortcutStore`。
/// - **系统固定**：⌘, 设置、⌃⌘S 侧边栏、⌘0 主窗口、⌘U 检查更新、⌘Q 退出 —— 由 macOS/SwiftUI 提供，
///   只做展示（收录），避免用户以为"漏了"。
struct ShortcutsSettingsView: View {

    @Environment(ShortcutStore.self) private var shortcuts
    @State private var recording: AppShortcut?
    @State private var monitor: Any?

    var body: some View {
        Form {
            ForEach(AppShortcut.Group.allCases, id: \.self) { group in
                if !shortcutsIn(group).isEmpty {
                    Section {
                        ForEach(shortcutsIn(group)) { shortcut in
                            row(shortcut)
                        }
                    } header: {
                        Text(title(for: group))
                    }
                }
            }

            Section {
                ForEach(Array(Self.fixed.enumerated()), id: \.offset) { _, item in
                    LabeledContent(item.title) {
                        Text(item.keys)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Provided by the system")
            } footer: {
                Text("These are handled by macOS and cannot be changed here.")
            }

            Section {
                Text("OrzMC 处于活跃状态时，应用内快捷键先于文本输入生效；正在用输入法拼写时一律让位给候选词。")
                Text("系统快捷键（⌘Space、⌃↑ 等）和其它 App 注册的全局热键会在系统层先被拦下，本应用收不到——某条快捷键没反应时，先去「系统设置 → 键盘 → 快捷键」查是否被占用。")
            } header: {
                Text("Priority and conflicts")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
        .labeledContentStyle(.orzMCFieldRow(labelWidth: 150))
        .focusSection()
        .onDisappear { stopRecording() }
    }

    // MARK: 行

    private func row(_ shortcut: AppShortcut) -> some View {
        LabeledContent(shortcut.title) {
            HStack(spacing: OrzMCTheme.Spacing.sm) {
                Text(shortcuts.spec(for: shortcut).displayText)
                    .font(.body.monospaced())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(OrzMCTheme.Palette.controlFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .foregroundStyle(recording == shortcut ? OrzMCTheme.Palette.accent : Color.primary)

                Button(recording == shortcut ? "Press keys…" : "Record") {
                    if recording == shortcut { stopRecording() } else { startRecording(shortcut) }
                }
                .disabled(recording != nil && recording != shortcut)

                Button("Reset") { shortcuts.reset(shortcut) }
                    .disabled(!shortcuts.isCustomized(shortcut))
            }
        }
    }

    // MARK: 录制

    private func startRecording(_ shortcut: AppShortcut) {
        stopRecording()
        recording = shortcut
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Esc = 取消
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }
            guard let spec = ShortcutRecorder.spec(from: event) else { return nil }
            shortcuts.set(spec, for: shortcut)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        recording = nil
    }

    // MARK: 文案

    private func shortcutsIn(_ group: AppShortcut.Group) -> [AppShortcut] {
        AppShortcut.allCases.filter { $0.group == group }
    }

    private func title(for group: AppShortcut.Group) -> LocalizedStringKey {
        switch group {
        case .launch: return "Launch and console"
        case .navigation: return "Version list"
        case .lifecycle: return "Server lifecycle"
        }
    }

    /// 系统提供的快捷键（只展示）。
    private static let fixed: [(title: LocalizedStringKey, keys: String)] = [
        ("Settings…", "⌘,"),
        ("Show/Hide Sidebar", "⌃⌘S"),
        ("Show Main Window", "⌘0"),
        ("Check for Updates…", "⌘U"),
        ("Close Window (settings, console)", "Esc"),
        ("Quit OrzMC", "⌘Q"),
    ]
}
