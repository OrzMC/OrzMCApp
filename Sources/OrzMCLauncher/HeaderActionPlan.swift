//
//  HeaderActionPlan.swift
//  OrzMCLauncher
//

import CoreGraphics

/// 实例表头右端「动作按钮」的排布方案。
///
/// 需求（2026-10-22）：**尽量全部内联**显示（按竖线分组），只有宽度不够时才把
/// 优先级最低的那组收进 `⋯` 菜单——而不是像以前那样无条件把「终止 / 删除」藏起来，
/// 让人以为没有这个功能。
///
/// 纯逻辑：只做宽度估算与取舍，不碰任何 SwiftUI 类型，便于单测。
public struct HeaderActionPlan: Equatable {

    /// 一组动作（视觉上用竖线分隔）。
    public enum Group: String, CaseIterable, Sendable {
        /// 看与管：控制台、插件。
        case inspect
        /// 生命周期：启动、重启、停止。
        case lifecycle
        /// 高危：终止、删除。
        case danger
    }

    /// 内联显示的分组（按渲染顺序）。
    public let inline: [Group]
    /// 收进 `⋯` 菜单的分组。
    public let overflow: [Group]

    // MARK: - 尺寸常量（与 FormSectionHeader 的图标按钮保持一致）

    /// 单个图标按钮的宽度（≈26pt 图标 + 一点 hover 余量）。
    public static let buttonWidth: CGFloat = 28
    /// 一组与一组之间的竖线（1pt 线 + 两侧留白）。
    public static let dividerWidth: CGFloat = 9
    /// 同组内按钮间距 / 组与 `⋯` 之间间距。
    public static let spacing: CGFloat = 8
    /// `⋯` 溢出菜单按钮本身的宽度。
    public static let overflowButtonWidth: CGFloat = 28

    /// 计算排布方案。
    ///
    /// - Parameters:
    ///   - availableWidth: 表头右端实际可用的宽度。
    ///   - present: 每组出现的按钮个数（没有的组不要传，或传 0）。
    public static func plan(availableWidth: CGFloat, present: [Group: Int]) -> HeaderActionPlan {
        // 保持固定的展示顺序，与 `Group.allCases` 一致。
        let groups = Group.allCases.filter { (present[$0] ?? 0) > 0 }
        guard !groups.isEmpty else { return HeaderActionPlan(inline: [], overflow: []) }

        // 依次尝试：全内联 → 收 danger → 再收 lifecycle → 全收进 ⋯。
        for cut in 0...groups.count {
            let inline = Array(groups.prefix(groups.count - cut))
            let overflow = Array(groups.suffix(cut))
            if width(inline: inline, overflow: overflow, present: present) <= availableWidth {
                return HeaderActionPlan(inline: inline, overflow: overflow)
            }
        }
        return HeaderActionPlan(inline: [], overflow: groups)
    }

    /// 估算「这些组内联 + 这些组进 ⋯」所需的总宽度。
    static func width(inline: [Group], overflow: [Group], present: [Group: Int]) -> CGFloat {
        var total: CGFloat = 0
        var buttons = 0
        for group in inline {
            buttons += present[group] ?? 0
        }
        if buttons > 0 {
            total += CGFloat(buttons) * buttonWidth
            total += CGFloat(buttons - inline.count) * spacing      // 组内按钮间距
            total += CGFloat(inline.count - 1) * dividerWidth       // 组间竖线
        }
        if !overflow.isEmpty {
            if buttons > 0 {
                total += dividerWidth + spacing                     // 与 `⋯` 之间的分隔
            }
            total += overflowButtonWidth
        }
        return total
    }
}
