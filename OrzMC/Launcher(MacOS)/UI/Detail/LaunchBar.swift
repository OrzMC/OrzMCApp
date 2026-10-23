//
//  LaunchBar.swift
//  OrzMC
//

import Game
import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 详情页顶部的「启动条」：**启动目标 / 玩家名（仅客户端）/ Java 需求与状态 / 启动**。
///
/// 为什么放在页面里而不是窗口标题栏（2026-10-22 第十七轮，维护者意见）：
/// 标题栏里的控件只能用系统工具栏样式，做不了定制外观；而且相邻控件会被 macOS 26 并进同一个胶囊
/// （Java 状态和玩家名输入框糊成「Java joker」）。放回正文后可以用设计系统的面板/胶囊自己排版。
///
/// ```
/// ┌───────────────────────────────────────────────────────────────┐
/// │  ▭ 客户端 · Vanilla ⌄   [ joker ]           ✓ Java 25   ▶    │
/// └───────────────────────────────────────────────────────────────┘
/// ```
struct LaunchBar: View {

    @Environment(AppModel.self) private var app
    @Environment(ShortcutStore.self) private var shortcuts
    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 10) {
            targetMenu

            if app.gameMode == .client {
                usernameField
            }

            Spacer(minLength: 8)

            javaStatus
            startButton
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        // 自定义「启动卡」：不用列表项那套 `.orzMCPanel()`，改成品牌色薄渐变 + 强调描边 + 大圆角，
        // 让它在视觉上明显区别于下面的实例卡片（它承载的是"这一版要启动什么"）。
        .background {
            let shape = RoundedRectangle(cornerRadius: OrzMCTheme.Radius.lg, style: .continuous)
            shape
                .fill(OrzMCTheme.Palette.panelFill)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                OrzMCTheme.Palette.accent.opacity(0.10),
                                OrzMCTheme.Palette.accent.opacity(0.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape.strokeBorder(OrzMCTheme.Palette.accent.opacity(0.22), lineWidth: 1)
                }
        }
        .focusSection()
        // ⌘T：循环切换启动目标（客户端 Vanilla/Fabric → 服务端四个核心）。
        .onAppear { installTargetShortcut() }
        .onDisappear { removeTargetShortcut() }
    }

    /// 菜单里的顺序（快捷键按这个顺序走）。
    private var targetOrder: [LaunchTargetKey] {
        SettingsModel.ClientKind.allCases.map { .client($0.rawValue) }
            + SettingsModel.ServerSoftware.allCases.map { .server($0.rawValue) }
    }

    private func cycleLaunchTarget() {
        let order = targetOrder
        guard let current = order.firstIndex(of: targetBinding.wrappedValue), !order.isEmpty else { return }
        targetBinding.wrappedValue = order[(current + 1) % order.count]
    }

    private func installTargetShortcut() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 有弹层/正在输入时不抢键。
            guard NSApp.keyWindow?.attachedSheet == nil else { return event }
            if let editor = NSApp.keyWindow?.firstResponder as? NSTextView, editor.isFieldEditor {
                return event
            }
            let spec = shortcuts.spec(for: .cycleTarget)
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var expected: NSEvent.ModifierFlags = []
            if spec.modifiers.contains(.command) { expected.insert(.command) }
            if spec.modifiers.contains(.shift) { expected.insert(.shift) }
            if spec.modifiers.contains(.option) { expected.insert(.option) }
            if spec.modifiers.contains(.control) { expected.insert(.control) }
            guard flags == expected,
                  let typed = event.charactersIgnoringModifiers?.lowercased(),
                  typed == spec.key.lowercased()
            else { return event }
            cycleLaunchTarget()
            return nil
        }
    }

    private func removeTargetShortcut() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// 一次选择搞定「哪一端 + 哪种类型」：菜单分「客户端 / 服务端」两组。
    private var targetMenu: some View {
        Menu {
            Picker("Launch target", selection: targetBinding) {
                Section("Client") {
                    ForEach(SettingsModel.ClientKind.allCases) { kind in
                        Label("Client · \(kind.rawValue)", systemImage: "macwindow")
                            .tag(LaunchTargetKey.client(kind.rawValue))
                    }
                }
                Section("Server") {
                    ForEach(SettingsModel.ServerSoftware.allCases) { software in
                        Label("Server · \(software.rawValue)", systemImage: "server.rack")
                            .tag(LaunchTargetKey.server(software.rawValue))
                    }
                }
            }
            .pickerStyle(.inline)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: targetGlyph)
                    .foregroundStyle(.secondary)
                Text(targetTitle)
                    .font(.callout)
            }
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(OrzMCTheme.Palette.controlFill, in: Capsule())
        // 鼠标滚轮切换启动目标（不动键盘也能换）。
        .disabled(app.launch.isLaunching)
        .help("Choose what to launch: client (Vanilla / Fabric) or a server core")
        .accessibilityLabel(Text("Launch target"))
    }

    private var targetTitle: String {
        if app.gameMode == .client {
            return String(localized: "Client · \(app.settings.clientType.rawValue)")
        }
        return String(localized: "Server · \(app.settings.serverSoftware.rawValue)")
    }

    private var targetGlyph: String {
        app.gameMode == .client ? "macwindow" : "server.rack"
    }

    private var targetBinding: Binding<LaunchTargetKey> {
        Binding(
            get: {
                app.gameMode == .client
                    ? .client(app.settings.clientType.rawValue)
                    : .server(app.settings.serverSoftware.rawValue)
            },
            set: { key in
                switch key {
                case let .client(raw):
                    guard let kind = SettingsModel.ClientKind(rawValue: raw) else { return }
                    app.gameMode = .client
                    app.settings.clientType = kind
                case let .server(raw):
                    guard let software = SettingsModel.ServerSoftware(rawValue: raw) else { return }
                    app.gameMode = .server
                    app.settings.serverSoftware = software
                }
            }
        )
    }

    // MARK: - 玩家名（仅客户端）

    private var usernameField: some View {
        HStack(spacing: 6) {
            Image(systemName: "person.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            TextField("", text: usernameBinding, prompt: Text("Enter player name"))
                .textFieldStyle(.plain)
                .labelsHidden()
                .multilineTextAlignment(.leading)
                .textContentType(.username)
                .autocorrectionDisabled()
                .controlSize(.small)
                .disabled(app.launch.isLaunching)
                .onSubmit { app.start() }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(OrzMCTheme.Palette.controlFill, in: Capsule())
        .overlay {
            // 输入框比"下拉胶囊"多一道细描边：一眼能看出这里可以打字。
            // 客户端模式没填名字时描边转警告色——启动按钮为什么是灰的，原因就在这。
            Capsule().strokeBorder(usernameIsMissing
                ? OrzMCTheme.Palette.warning.opacity(0.45)
                : OrzMCTheme.Palette.panelBorder, lineWidth: 1)
        }
        .frame(width: 190)
        .help("Player name used for the offline client launch")
        .accessibilityLabel(Text("Username"))
    }

    private var usernameIsMissing: Bool {
        app.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var usernameBinding: Binding<String> {
        Binding(get: { app.username }, set: { app.username = $0 })
    }

    // MARK: - Java 需求与状态

    /// 「该版本需要哪个 Java + 本机是否满足」；点一下重新扫描。
    private var javaStatus: some View {
        Button {
            app.java.refresh()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: javaGlyph)
                Text(javaTitle)
                    .font(OrzMCTheme.Typography.numeric)
            }
            .foregroundStyle(javaColor)
        }
        .buttonStyle(.borderless)
        .help(javaHelp)
        .accessibilityLabel(Text(javaHelp))
    }

    private var javaTitle: String {
        guard let required = app.java.requiredMajor else { return "Java" }
        return "Java \(required)"
    }

    private var javaGlyph: String {
        switch app.java.status {
        case .valid: return "checkmark.seal.fill"
        case .missing: return "arrow.down.circle"
        case .unknown: return "questionmark.circle"
        }
    }

    private var javaColor: Color {
        switch app.java.status {
        case .valid: return OrzMCTheme.Palette.success
        case .missing: return OrzMCTheme.Palette.warning
        case .unknown: return OrzMCTheme.Palette.idle
        }
    }

    /// 悬停/辅助功能文案：需求 + 本机情况 + 可点击重扫。
    private var javaHelp: String {
        let installed = app.java.installedMajors.isEmpty
            ? String(localized: "None")
            : app.java.installedMajors.map(String.init).formatted(.list(type: .and))
        guard let required = app.java.requiredMajor else {
            return String(localized: "Java requirement is unknown until a version is selected. Click to rescan.")
        }
        switch app.java.status {
        case .valid:
            return String(localized: "This version needs Java \(required); installed: \(installed). Click to rescan.")
        case .missing:
            return String(localized: "This version needs Java \(required); it will be installed on launch. Installed: \(installed). Click to rescan.")
        case .unknown:
            return String(localized: "Could not detect Java runtimes. Installed: \(installed). Click to rescan.")
        }
    }

    // MARK: - 启动

    private var startButton: some View {
        Button {
            app.start()
        } label: {
            Label("Start \(app.localizedGameModeTitle)", systemImage: "play.fill")
                .labelStyle(.titleAndIcon)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        // ⌘↩：与按钮同一个 action（可改，见设置页「快捷键」）。
        .keyboardShortcut(shortcuts.spec(for: .start).keyEquivalent,
                          modifiers: shortcuts.spec(for: .start).eventModifiers)
        .disabled(!app.canStart)
        .help(startHelp)
        .accessibilityLabel(Text("Start \(app.localizedGameModeTitle)"))
    }

    private var startHelp: String {
        if app.isCurrentInstanceRunning {
            return String(localized: "\(app.localizedGameModeTitle) is already running")
        }
        return app.canStart
            ? String(localized: "Start \(app.localizedGameModeTitle)")
            : String(localized: "Select a version, enter a user name, and check the memory settings")
    }
}

/// 启动目标的标识（`Picker` 需要 `Hashable` tag）。
/// 用字符串包一层，避免为"客户端/服务端 + 类型"再造一个与设置同步的大枚举。
enum LaunchTargetKey: Hashable {
    case client(String)
    case server(String)
}
