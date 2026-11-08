//
//  ActionButton.swift
//  OrzMCDesignSystem
//
//  卡片表头 / 行尾的**图标动作按钮**与**模式按钮组**。
//
//  为什么要有这两个组件（2026-11-08 维护者反馈）：
//  主窗口（实例卡片表头）和服务器窗口（服务器卡片）各写了一套图标按钮：
//  · 主窗口把 `.foregroundStyle(Palette.idle)` 写在按钮上 → `.disabled` 之后颜色不变，
//    一排启动/重启/停止/删除全是同一个灰，"能不能点"完全看不出来；
//  · 服务器窗口后来补了 hover 底色、更大的命中区和 disabled 透明度，两边又不一致。
//
//  这里把规则收成一份（HIG Buttons：按钮要有按压/悬停反馈；状态要看得出来）：
//  · 可用：`Palette.control`（primary 0.72，深色面板上约 6:1）；
//  · 不可用：`opacity 0.35`（`.foregroundStyle` 会盖掉系统对 disabled 的调暗，必须自己补）；
//  · 悬停：`Palette.subtleFill` 圆角底；按下由 `.borderless` 提供；
//  · 命中区：macOS 22×22 / iOS 32×32（卡片里一排 5 个图标也不能把名字挤没）。
//
//  平台约束：本文件在 `Sources/`（平台无关），只用 SwiftUI 语义色，不 import AppKit/UIKit。
//

import SwiftUI

public struct OrzMCActionButton: View {
    private let title: LocalizedStringKey
    private let systemImage: String
    private let tint: Color
    private let help: LocalizedStringKey?
    private let isEnabled: Bool
    private let identifier: String?
    private let accessibilityValue: String?
    private let action: () -> Void

    /// 外面套 `.disabled(...)` 时 SwiftUI 只会把它写进环境；这里要和自己的 `isEnabled` 合并，
    /// 否则"表头整体忙碌 → 全部禁用"那条路径不会变暗。
    @Environment(\.isEnabled) private var isEnabledByEnvironment
    @State private var isHovering = false

    public init(
        title: LocalizedStringKey,
        systemImage: String,
        tint: Color = OrzMCTheme.Palette.control,
        help: LocalizedStringKey? = nil,
        isEnabled: Bool = true,
        identifier: String? = nil,
        accessibilityValue: String? = nil,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.help = help
        self.isEnabled = isEnabled
        self.identifier = identifier
        self.accessibilityValue = accessibilityValue
        self.action = action
    }

    private var effectiveEnabled: Bool { isEnabled && isEnabledByEnvironment }

    /// 命中区：触控按 32，指针按 22（与服务器窗口同一套）。
    private static var hitSize: CGFloat {
        #if os(iOS)
        return 32
        #else
        return 22
        #endif
    }

    private static var symbolSize: CGFloat {
        #if os(iOS)
        return 15
        #else
        return 13
        #endif
    }

    public var body: some View {
        button
            .buttonStyle(.borderless)
            .foregroundStyle(tint)
            .opacity(effectiveEnabled ? 1 : 0.35)
            .modifier(OptionalHelp(help: help))
    }

    @ViewBuilder
    private var button: some View {
        if let identifier {
            base.accessibilityIdentifier(identifier)
        } else {
            base
        }
    }

    private var base: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: Self.symbolSize))
                .frame(width: Self.hitSize, height: Self.hitSize)
                .background {
                    RoundedRectangle(cornerRadius: OrzMCTheme.Radius.sm, style: .continuous)
                        .fill(OrzMCTheme.Palette.subtleFill.opacity(isHovering && effectiveEnabled ? 0.9 : 0))
                }
                .contentShape(Rectangle())
        }
        .accessibilityLabel(Text(title))
        .modifier(OptionalAccessibilityValue(value: accessibilityValue))
        .onHover { isHovering = $0 }
    }
}

/// 「全部折叠 / 全部展开」两个动作按钮（模式控件）。
///
/// 两个窗口（主窗口实例详情 / 服务器窗口）共用同一份：以前各写一遍，
/// 主窗口用强调色做选中底、服务器窗口用中性底，同一个控件在两个窗口里长得不一样。
///
/// 为什么不用 `Picker`：它是**两个动作**（点了就设置全局档位），不是"选择某一项"；
/// 而且单组折叠后全局值没变，`Picker` 再点同一档不会触发 `onChange`（主窗口 2026-10-22 踩过）。
public struct OrzMCDisplayModeControls: View {
    /// 当前是否"全部折叠"（不代表单组覆盖）。
    private let isCollapsed: Bool
    /// 存在单组覆盖（= 混合状态）：两档都不高亮。
    private let isMixed: Bool
    private let collapseIdentifier: String?
    private let expandIdentifier: String?
    private let onCollapse: () -> Void
    private let onExpand: () -> Void

    public init(
        isCollapsed: Bool,
        isMixed: Bool = false,
        collapseIdentifier: String? = nil,
        expandIdentifier: String? = nil,
        onCollapse: @escaping () -> Void,
        onExpand: @escaping () -> Void
    ) {
        self.isCollapsed = isCollapsed
        self.isMixed = isMixed
        self.collapseIdentifier = collapseIdentifier
        self.expandIdentifier = expandIdentifier
        self.onCollapse = onCollapse
        self.onExpand = onExpand
    }

    public var body: some View {
        HStack(spacing: 2) {
            modeButton(
                systemImage: "rectangle.compress.vertical",
                label: "Collapse All",
                isActive: isCollapsed && !isMixed,
                identifier: collapseIdentifier,
                action: onCollapse
            )
            modeButton(
                systemImage: "rectangle.expand.vertical",
                label: "Expand All",
                isActive: !isCollapsed && !isMixed,
                identifier: expandIdentifier,
                action: onExpand
            )
        }
        .padding(3)
        .background(
            OrzMCTheme.Palette.controlFill,
            in: RoundedRectangle(cornerRadius: OrzMCTheme.Radius.md, style: .continuous)
        )
        .help("Collapse or expand every card")
    }

    private static var buttonSize: (width: CGFloat, height: CGFloat) {
        #if os(iOS)
        return (34, 30)
        #else
        return (30, 22)
        #endif
    }

    private func modeButton(
        systemImage: String,
        label: LocalizedStringKey,
        isActive: Bool,
        identifier: String?,
        action: @escaping () -> Void
    ) -> some View {
        let size = Self.buttonSize
        return Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .font(.system(size: 13))
                .frame(width: size.width, height: size.height)
                .foregroundStyle(isActive ? Color.primary : Color.secondary)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: OrzMCTheme.Radius.sm, style: .continuous)
                            .fill(OrzMCTheme.Palette.selectionNeutral)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
        .modifier(OptionalIdentifier(identifier: identifier))
    }
}

/// `help` 只在有值时才挂（`.help("")` 会留下一个空气泡）。
private struct OptionalHelp: ViewModifier {
    let help: LocalizedStringKey?

    func body(content: Content) -> some View {
        if let help {
            content.help(help)
        } else {
            content
        }
    }
}

private struct OptionalAccessibilityValue: ViewModifier {
    let value: String?

    func body(content: Content) -> some View {
        if let value, !value.isEmpty {
            content.accessibilityValue(Text(verbatim: value))
        } else {
            content
        }
    }
}

private struct OptionalIdentifier: ViewModifier {
    let identifier: String?

    func body(content: Content) -> some View {
        if let identifier {
            content.accessibilityIdentifier(identifier)
        } else {
            content
        }
    }
}
