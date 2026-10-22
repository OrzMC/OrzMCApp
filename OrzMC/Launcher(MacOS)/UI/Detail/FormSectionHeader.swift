//
//  FormSectionHeader.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 实例栏的表头：左「标题 + 状态」，右「控制台 / 插件 / 生命周期 / 高危菜单」。
///
/// 可见性是 `Form` 的 Section header；语义上它是这一栏的动作区。
struct FormSectionHeader: View {
    typealias ButtonAction = () -> Void

    let title: LocalizedStringKey
    /// 悬停提示 / 辅助功能里附带的实例名（`1.21.5 Paper`）。
    var helpTitle: String = ""
    /// 运行状态（服务端/客户端都有：Running / Stopped / Starting… / Restarting…）。
    var statusText: String?
    var statusStyle: OrzMCStatusStyle = .idle
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
    /// 删除（**高危**：删文件，不可恢复）——点击后需二次确认。
    var deleteBtnAction: ButtonAction

    var body: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            // 左：标题 + 状态（同一套状态徽标，颜色只做辅助，文字始终可读）
            Text(title)
                .font(.headline)
            if let statusText {
                OrzMCStatusBadge(verbatim: statusText, style: statusStyle)
            }

            Spacer(minLength: OrzMCTheme.Spacing.md)

            // 右：操作按钮（高危动作带确认，执行中全禁用）
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            HStack(spacing: OrzMCTheme.Spacing.sm) {
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
                if startBtnAction != nil || restartBtnAction != nil || stopBtnAction != nil || terminateBtnAction != nil {
                    groupSeparator
                }
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
                // 「不可逆 / 高危」动作收进溢出菜单：日常操作（Start/Restart/Stop）
                // 留在外面，Terminate/Delete 不再和它们抢同一行。
                if terminateBtnAction != nil || deleteBtnAction != nil {
                    groupSeparator
                    Menu {
                        if let terminateBtnAction {
                            Button(role: .destructive, action: terminateBtnAction) {
                                Label("Terminate…", systemImage: "xmark.octagon")
                            }
                            .disabled(!(availability?.canTerminate ?? true))
                        }
                        if let terminateBtnAction, deleteBtnAction != nil {
                            Divider()
                        }
                        Button(role: .destructive, action: deleteBtnAction) {
                            Label("Delete…", systemImage: "trash")
                        }
                        .disabled(!(availability?.canDelete ?? true))
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                            .labelStyle(.iconOnly)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .foregroundStyle(OrzMCTheme.Palette.idle)
                    .help("More destructive actions (Terminate / Delete — both ask for confirmation)")
                    .disabled(isBusy)
                }
            }
            .disabled(isBusy)
        }
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
