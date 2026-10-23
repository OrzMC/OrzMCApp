//
//  FormSectionHeader.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 实例栏的表头：左「标题 + [当前] + 状态」，右「动作按钮」。
///
/// 动作区按 `HeaderActionPlan` **尽量全部内联**（控制台/插件 ｜ 启动/重启/停止 ｜ 终止/删除），
/// 只有窗口太窄放不下时才把靠后的组收进 `⋯`，不再无条件把高危动作藏起来。
/// 可见性是 `Form` 的 Section header；语义上它是这一栏的动作区。
struct FormSectionHeader: View {
    typealias ButtonAction = () -> Void

    let title: LocalizedStringKey
    /// 悬停提示 / 辅助功能里附带的实例名（`1.21.5 Paper`）。
    var helpTitle: String = ""
    /// 运行状态（服务端/客户端都有：Running / Stopped / Starting… / Restarting…）。
    var statusText: String?
    var statusStyle: OrzMCStatusStyle = .idle
    /// 这一栏是不是工具栏"当前启动类型"指向的实例（6 栏并列时需要区分，否则看起来一模一样）。
    var isCurrentType: Bool = false
    /// 该实例有操作在进行（启动/停止/重启中）→ **全部按钮禁用**，防连点。
    var isBusy: Bool = false
    /// 生命周期按钮的可用性（`nil` = 该实例不提供生命周期控制，例如客户端）。
    var availability: InstanceActionAvailability?
    /// 打开该实例自己的控制台（客户端 + 四种核心各一个，入口就在自己这一栏）。
    var consoleBtnAction: ButtonAction?
    var consoleIsLive: Bool = false
    /// 插件管理（仅支持插件的核心，如 Paper）。
    var pluginsBtnAction: ButtonAction?
    /// 启动（无确认）。
    var startBtnAction: ButtonAction?
    /// 重启（先停后起，会断开玩家 → 二次确认）。
    var restartBtnAction: ButtonAction?
    /// 优雅停止（送 `stop` → 让服务端自己存档退出；会断开玩家 → 二次确认）。
    var stopBtnAction: ButtonAction?
    /// 终止进程（`SIGTERM`→`SIGKILL`，可能丢存档 → 二次确认）。
    var terminateBtnAction: ButtonAction?
    /// 这一栏是否展开（折叠时只显示本行；点标题或左侧箭头切换）。
    var isExpanded: Bool = true
    /// 折叠/展开这一栏；`nil` = 不提供该交互。
    var toggleAction: ButtonAction?
    /// 删除（**高危**：删文件，不可恢复）——点击后需二次确认。
    var deleteBtnAction: ButtonAction

    /// 动作区实际可用宽度（由背景 `GeometryReader` 测出）。
    /// DEBUG 可用 `ORZMC_ACTION_SPACE=<pt>` 强制一个宽度，回归"窗口太窄时进 ⋯ 菜单"的排布。
    @State private var actionSpace: CGFloat = .infinity

    /// 实际用于排版的宽度：DEBUG 下可用 `ORZMC_ACTION_SPACE` 强制（回归"窄窗口 → ⋯ 菜单"）。
    private var effectiveActionSpace: CGFloat {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["ORZMC_ACTION_SPACE"], let value = Double(raw) {
            return CGFloat(value)
        }
        #endif
        return actionSpace
    }

    var body: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            // 左：标题 + 状态（同一套状态徽标，颜色只做辅助，文字始终可读）
            Button(action: { toggleAction?() }) {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 12, alignment: .center)
                    Text(title)
                        .font(.headline)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .disabled(toggleAction == nil)
            .help(isExpanded ? "Collapse this instance" : "Expand this instance")
            .accessibilityLabel(Text(isExpanded ? "Collapse this instance" : "Expand this instance"))
            if let statusText {
                OrzMCStatusBadge(verbatim: statusText, style: statusStyle)
            }

            // 右：动作区。宽度由 `HStack` 剩余空间决定，先用 `HeaderActionPlan` 估算
            // "能内联几组"，放不下的才收进 `⋯`（不再是"终止/删除永远藏在菜单里"）。
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            actions
                .frame(maxWidth: .infinity, alignment: .trailing)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(key: ActionSpaceKey.self, value: proxy.size.width)
                    }
                )
                .onPreferenceChange(ActionSpaceKey.self) { actionSpace = $0 }
                .disabled(isBusy)
        }
    }

    // MARK: - 动作区

    /// 各组里出现了几个按钮（`HeaderActionPlan` 按这个算宽度）。
    private var presentGroups: [HeaderActionPlan.Group: Int] {
        [
            .inspect: (consoleBtnAction == nil ? 0 : 1) + (pluginsBtnAction == nil ? 0 : 1),
            .lifecycle: (startBtnAction == nil ? 0 : 1)
                + (restartBtnAction == nil ? 0 : 1)
                + (stopBtnAction == nil ? 0 : 1),
            .danger: 1 + (terminateBtnAction == nil ? 0 : 1),   // 删除按钮始终存在
        ]
    }

    private var plan: HeaderActionPlan {
        HeaderActionPlan.plan(availableWidth: effectiveActionSpace, present: presentGroups)
    }

    private var actions: some View {
        let plan = plan
        return HStack(spacing: HeaderActionPlan.spacing) {
            ForEach(Array(plan.inline.enumerated()), id: \.offset) { index, group in
                if index > 0 {
                    groupSeparator
                }
                buttons(for: group)
            }
            if !plan.overflow.isEmpty {
                if !plan.inline.isEmpty {
                    groupSeparator
                }
                overflowMenu(groups: plan.overflow)
            }
        }
    }

    @ViewBuilder
    private func buttons(for group: HeaderActionPlan.Group) -> some View {
        switch group {
        case .inspect:
            if let consoleBtnAction {
                iconButton(
                    "Console",
                    systemImage: consoleIsLive ? "terminal.fill" : "terminal",
                    color: consoleIsLive ? OrzMCTheme.Palette.success : OrzMCTheme.Palette.idle,
                    help: consoleIsLive ? "Open console (running)" : "Open console",
                    action: consoleBtnAction
                )
            }
            if let pluginsBtnAction {
                iconButton(
                    "Plugins",
                    systemImage: "puzzlepiece.extension",
                    color: OrzMCTheme.Palette.idle,
                    help: "Manage plugins for this instance",
                    action: pluginsBtnAction
                )
            }
        case .lifecycle:
            if let startBtnAction {
                iconButton(
                    "Start",
                    systemImage: "play.circle",
                    color: OrzMCTheme.Palette.idle,
                    help: "Start this server",
                    action: startBtnAction
                )
                .disabled(!(availability?.canStart ?? true))
            }
            if let restartBtnAction {
                iconButton(
                    "Restart",
                    systemImage: "arrow.clockwise.circle",
                    color: OrzMCTheme.Palette.idle,
                    help: "Restart = graceful stop, then start again",
                    action: restartBtnAction
                )
                .disabled(!(availability?.canRestart ?? true))
            }
            if let stopBtnAction {
                iconButton(
                    "Stop",
                    systemImage: "stop.circle",
                    color: OrzMCTheme.Palette.idle,
                    help: "Send `stop` so the server saves and exits normally",
                    action: stopBtnAction
                )
                .disabled(!(availability?.canStop ?? true))
            }
        case .danger:
            if let terminateBtnAction {
                Button(role: .destructive, action: terminateBtnAction) {
                    Label("Terminate…", systemImage: "xmark.octagon")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(OrzMCTheme.Palette.idle)
                .help("Terminate the process (may lose unsaved progress)")
                .disabled(!(availability?.canTerminate ?? true))
            }
            Button(role: .destructive, action: deleteBtnAction) {
                Label("Delete…", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(OrzMCTheme.Palette.idle)
            .help("Delete this instance's folder (asks for confirmation)")
            .disabled(!(availability?.canDelete ?? true))
        }
    }

    /// 空间不足时才出现的 `⋯`：按原顺序收进来，菜单里带文字标签。
    private func overflowMenu(groups: [HeaderActionPlan.Group]) -> some View {
        Menu {
            ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                if index > 0 { Divider() }
                switch group {
                case .inspect:
                    if let consoleBtnAction {
                        Button(action: consoleBtnAction) {
                            Label("Console", systemImage: consoleIsLive ? "terminal.fill" : "terminal")
                        }
                    }
                    if let pluginsBtnAction {
                        Button(action: pluginsBtnAction) {
                            Label("Plugins", systemImage: "puzzlepiece.extension")
                        }
                    }
                case .lifecycle:
                    if let startBtnAction {
                        Button(action: startBtnAction) { Label("Start this server", systemImage: "play.circle") }
                            .disabled(!(availability?.canStart ?? true))
                    }
                    if let restartBtnAction {
                        Button(action: restartBtnAction) { Label("Restart…", systemImage: "arrow.clockwise.circle") }
                            .disabled(!(availability?.canRestart ?? true))
                    }
                    if let stopBtnAction {
                        Button(action: stopBtnAction) { Label("Stop…", systemImage: "stop.circle") }
                            .disabled(!(availability?.canStop ?? true))
                    }
                case .danger:
                    if let terminateBtnAction {
                        Button(role: .destructive, action: terminateBtnAction) {
                            Label("Terminate…", systemImage: "xmark.octagon")
                        }
                        .disabled(!(availability?.canTerminate ?? true))
                    }
                    Button(role: .destructive, action: deleteBtnAction) {
                        Label("Delete…", systemImage: "trash")
                    }
                    .disabled(!(availability?.canDelete ?? true))
                }
            }
        } label: {
            Label("More actions", systemImage: "ellipsis.circle")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(OrzMCTheme.Palette.idle)
        .help("More actions (do not fit in this window width)")
    }

    /// 按钮分组之间的一道细线：把「看/管」与「生命周期」与「删除」视觉上分开。
    private var groupSeparator: some View {
        Divider()
            .frame(height: 12)
    }

    /// `help` 用 `LocalizedStringKey`：以前是 `String` 插值（`"Open \(helpTitle) console"`），
    /// 既不会被 Xcode 提取成 key，运行时也匹配不到任何 `%@` 条目，中文界面永远是英文提示。
    /// 实例名交给 `accessibilityValue`，VoiceOver 会读成「Open console，1.21.5 Paper」。
    private func iconButton(
        _ label: LocalizedStringKey,
        systemImage: String,
        color: Color,
        help: LocalizedStringKey,
        action: @escaping ButtonAction
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
        }
        // `.borderless` 保留系统 hover/按下反馈；`.plain` 在 macOS 上几乎没有可点击感。
        .buttonStyle(.borderless)
        .foregroundStyle(color)
        .help(help)
        .accessibilityValue(Text(verbatim: helpTitle))
    }
}

/// 动作区宽度测量（表头右端可用空间）。
private struct ActionSpaceKey: PreferenceKey {
    static let defaultValue: CGFloat = .infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = min(value, nextValue())
    }
}
