//
//  RemoteInstanceRow.swift
//  OrzMC
//
//  **实例行的通用骨架**（`docs/app-ui-design.md` §15.9 之前的跨端重构项）。
//
//  两家供应商的实例行以前各写一遍：
//    · exaroton：`名称 + 徽标` / id / 标签 / 地址 / MOTD，整行是 `NavigationLink`；
//    · MCSM：`名称 + 徽标` + 地址，右侧玩家数与 `⋯` 菜单，点名称开控制台 sheet。
//  字段顺序其实一样（标题行 → 明细 → 右侧动作），只是排版代码各自复制了一份，
//  于是大字号下一边会挤、另一边不挤，右边缘也对不齐。这里把**结构**收成一处：
//
//      heading（`RemoteInstanceHeading`：名称 + `OrzMCStatusBadge`）
//      details（供应商特有：id / 标签 / 地址 / MOTD）
//      trailing（供应商特有：箭头 / 玩家数 / 菜单）
//      footer（供应商特有：停止进度 / 动作错误）
//
//  骨架只管排版与可达性档位，不碰模型、不判状态、不改停止进度判定。
//
//  ⚠️ 三个插槽都要求**显式标签**（`details:` / `trailing:` / `footer:`）：带默认值的
//  `@ViewBuilder` 插槽 + 免标签尾随闭包会让"内容落在哪个槽"取决于重载解析，很难读也不安全。
//

import OrzMCDesignSystem
import SwiftUI

struct RemoteInstanceRow<Details: View, Trailing: View, Footer: View>: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let name: String
    var statusTitle: String? = nil
    var statusStyle: OrzMCStatusStyle = .idle
    /// 点"名称 + 明细"这块区域时执行（例如打开 MCSM 控制台 sheet）。
    /// `nil` = 这块自己不是按钮（外层通常套 `NavigationLink`，例如 exaroton 详情页）。
    var onTap: (() -> Void)? = nil
    /// `onTap` 那个按钮的自动化锚点。**只加在按钮上**，不加在行容器上（容器会把 identifier 下发给子元素）。
    var tapIdentifier: String? = nil
    /// 右侧显示跳转箭头（"点了会进下一页"，区别于"点了弹 sheet"）。
    var showsDisclosure = false

    @ViewBuilder var details: () -> Details
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
            if dynamicTypeSize.isAccessibilitySize {
                // 辅助功能大字号：右侧动作换到下一行，否则名称被压成两三个字一行。
                VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
                    primary
                    HStack(spacing: OrzMCTheme.Spacing.sm) {
                        trailing()
                        disclosure
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                    primary
                    Spacer(minLength: OrzMCTheme.Spacing.xs)
                    trailing()
                    disclosure
                }
            }
            footer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var primary: some View {
        if let onTap {
            if let tapIdentifier {
                tapButton(onTap).accessibilityIdentifier(tapIdentifier)
            } else {
                tapButton(onTap)
            }
        } else {
            headingAndDetails
        }
    }

    private func tapButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { headingAndDetails }
            .buttonStyle(.plain)
    }

    private var headingAndDetails: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
            RemoteInstanceHeading(name: name, statusTitle: statusTitle, statusStyle: statusStyle)
            details()
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var disclosure: some View {
        if showsDisclosure {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .accessibilityHidden(true)
        }
    }
}

extension RemoteInstanceRow where Footer == EmptyView {
    init(
        name: String,
        statusTitle: String? = nil,
        statusStyle: OrzMCStatusStyle = .idle,
        onTap: (() -> Void)? = nil,
        tapIdentifier: String? = nil,
        showsDisclosure: Bool = false,
        @ViewBuilder details: @escaping () -> Details,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.init(
            name: name,
            statusTitle: statusTitle,
            statusStyle: statusStyle,
            onTap: onTap,
            tapIdentifier: tapIdentifier,
            showsDisclosure: showsDisclosure,
            details: details,
            trailing: trailing,
            footer: { EmptyView() }
        )
    }
}

extension RemoteInstanceRow where Trailing == EmptyView, Footer == EmptyView {
    init(
        name: String,
        statusTitle: String? = nil,
        statusStyle: OrzMCStatusStyle = .idle,
        onTap: (() -> Void)? = nil,
        tapIdentifier: String? = nil,
        showsDisclosure: Bool = false,
        @ViewBuilder details: @escaping () -> Details
    ) {
        self.init(
            name: name,
            statusTitle: statusTitle,
            statusStyle: statusStyle,
            onTap: onTap,
            tapIdentifier: tapIdentifier,
            showsDisclosure: showsDisclosure,
            details: details,
            trailing: { EmptyView() },
            footer: { EmptyView() }
        )
    }
}
