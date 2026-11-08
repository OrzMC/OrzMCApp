//
//  ServerCard.swift
//  OrzMC
//
//  **服务器信息卡片**：自建 / exaroton / MCSManager 三个面共用同一套排布与动作样式。
//
//  为什么要有它（2026-11-07 维护者要求）：三处各自拼了一套"名称 + 状态 + 地址 + 标签 + 右侧动作"，
//  结果同一个窗口里出现三种观感 —— 自建是渐变面板、exaroton 是账号卡里的平铺行、
//  MCSManager 是"玩家数 + ⋯ 菜单"。样式一旦各写一遍，改一处就要改三处，而且很容易忘。
//
//  这里只统一**结构与动作样式**：
//
//  2026-11-08 视觉评审后补三件事（见 docs/app-ui-design.md §13）：
//  · `surface`：顶层卡片是面板，**面板里再放的行**用 `.plain`（不再"卡中卡"/玻璃套玻璃）；
//  · 标签从描边胶囊改成一行「`·` 分隔」的元信息（胶囊和状态徽章同形，看着像按钮）；
//  · 卡片可点时有 hover 反馈（macOS 上 `.plain` 按钮几乎没有可点感）。
//
//      heading  名称 + `OrzMCStatusBadge`（只走 `RemoteInstanceHeading`）
//      details  地址 / 标签（版本、玩家、延迟） / 备注（MOTD 等）
//      actions  右侧图标按钮组（`ServerActionGroup`，与主窗口实例卡头同一套：
//               图标 + 细分隔线，放不下才退化成 `⋯` 菜单）
//      footer   停止进度 / 错误提示
//
//  供应商特有的能力（exaroton 详情页、MCSM 控制台 sheet、强杀确认）仍留在各自界面，
//  这里不碰模型、不判状态。
//

import OrzMCDesignSystem
import SwiftUI

// MARK: - 卡片

/// 卡片表面的两种用法。
enum ServerCardSurface {
    /// 顶层卡片：自己是一块面板（玻璃/半透明填充 + 描边）。
    case panel
    /// 面板内部的**行**：不再套第二层面板，只留上下内边距（由外层卡片提供表面）。
    case plain
}

struct ServerCard<Actions: View, Footer: View>: View {
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isHovering = false

    let name: String
    var statusTitle: String? = nil
    var statusStyle: OrzMCStatusStyle = .idle
    /// 地址（等宽小字）。
    var address: String? = nil
    /// 标签（版本 / 玩家 / 延迟…），按顺序排成一行。
    var tags: [String] = []
    /// 备注（MOTD 之类），最多两行。
    var message: String? = nil
    /// 供应商特有条目（例如 exaroton 详情页要显示"可复制"的多个地址）。
    /// 用 `AnyView` 换掉泛型槽，避免 `ServerCard<A, B, C, D>` 的重载爆炸；这里只是几行文本，代价可忽略。
    var extra: AnyView? = nil
    /// 右侧是否显示 `›`（"点了会进下一页"，区别于"点了弹 sheet"）。
    var showsDisclosure = false
    /// 点"名称 + 明细"这块区域时执行（`nil` = 整卡由外层 `NavigationLink` 包裹）。
    var onTap: (() -> Void)? = nil
    /// `onTap` 那个按钮的自动化锚点。**只加在按钮上**，不加在容器上。
    var tapIdentifier: String? = nil
    /// 表面：顶层卡片 `.panel`；账号卡/面板卡**内部**的行用 `.plain`。
    var surface: ServerCardSurface = .panel

    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        ZStack(alignment: .topLeading) {
            // **整卡可点**：铺满卡片（含内边距）的一层按钮垫在内容下面。
            // 以前只有"名称 + 明细"那一个按钮能点，卡片右侧/下方的空白点了没反应
            // （2026-11-08 维护者反馈）。文本与动作按钮在它上面，点击照常落到各自控件；
            // 空白处则落到这一层。
            // 它对无障碍隐藏：焦点仍由内容里的主按钮（带 `tapIdentifier`）表达，避免两个同名按钮。
            if let onTap {
                Button(action: onTap) {
                    Color.clear.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityHidden(true)
            }

            cardContent
                .padding(.horizontal, surface == .panel ? OrzMCTheme.Spacing.md : 0)
                .padding(.vertical, surface == .panel ? OrzMCTheme.Spacing.md : OrzMCTheme.Spacing.sm)
        }
        .background {
            // 可点的卡片在指针悬停时给一层非常轻的底色：`.plain` / 玻璃面板上都要能看出"可以点"。
            if isTappable {
                RoundedRectangle(cornerRadius: OrzMCTheme.Radius.md, style: .continuous)
                    .fill(OrzMCTheme.Palette.subtleFill.opacity(isHovering ? 0.55 : 0))
            }
        }
        .modifier(ServerCardSurfaceModifier(surface: surface))
        .onHover { inside in
            guard isTappable else { return }
            isHovering = inside
        }
    }

    /// 卡片的可视内容（文本 + 动作 + footer）：布局按宽度等级决定。
    ///
    /// 不再用 `ViewThatFits` 逐卡自适应（2026-11-07 维护者截图反馈）：
    /// 同屏两张卡里一张把动作挤成一行、另一张折到第二行，看着像"按钮掉到底部"。
    /// · 紧凑宽度（iPhone 竖屏）：动作**固定**成卡片底部一条操作栏（上分隔线 + 右对齐）；
    /// · 常规宽度（iPad 横屏 / macOS）：动作与名称同一行（放不下才退化成底栏）。
    private var cardContent: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            if usesActionBar {
                VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                        primary
                        Spacer(minLength: 0)
                        disclosure
                    }
                    // 底部操作栏之前先放 footer（更新时间 / 停止进度 / 错误）：
                    // 否则 footer 会落到操作栏下面，看起来像在解释那排按钮。
                    footer()
                    actionBar
                }
            } else if hasActions {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                        primary
                        Spacer(minLength: OrzMCTheme.Spacing.sm)
                        actions()
                        disclosure
                    }
                    VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
                        HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                            primary
                            Spacer(minLength: 0)
                            disclosure
                        }
                        actionBar
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                    primary
                    Spacer(minLength: 0)
                    disclosure
                }
            }
            if !usesActionBar {
                footer()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 卡片本体是不是按钮（有 `onTap` 才是；`NavigationLink` 包卡片的写法已废弃）。
    private var isTappable: Bool { onTap != nil }

    /// 卡片上到底有没有动作按钮（`Actions == EmptyView` 的卡片不该留一条空的操作栏）。
    private var hasActions: Bool {
        (Actions.self as Any.Type) != (EmptyView.self as Any.Type)
    }

    /// 紧凑宽度下固定用底部操作栏；常规宽度留给 `ViewThatFits` 决定。
    private var usesActionBar: Bool {
        guard hasActions else { return false }
        #if os(iOS)
        return horizontalSizeClass == .compact
        #else
        return false
        #endif
    }

    /// 卡片底部操作栏：一条细分隔线 + 右对齐的动作组。
    @ViewBuilder
    private var actionBar: some View {
        VStack(alignment: .trailing, spacing: OrzMCTheme.Spacing.xs) {
            Divider().opacity(0.5)
            HStack(spacing: OrzMCTheme.Spacing.sm) {
                Spacer(minLength: 0)
                actions()
            }
            .frame(minHeight: 28)
        }
    }

    @ViewBuilder
    private var primary: some View {
        if let onTap {
            if let tapIdentifier {
                button(onTap).accessibilityIdentifier(tapIdentifier)
            } else {
                button(onTap)
            }
        } else {
            headingAndDetails
        }
    }

    private func button(_ action: @escaping () -> Void) -> some View {
        Button(action: action) { headingAndDetails }
            .buttonStyle(.plain)
    }

    private var headingAndDetails: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
            RemoteInstanceHeading(name: name, statusTitle: statusTitle, statusStyle: statusStyle)
            if let address {
                Text(address)
                    .font(.caption.monospaced())
                    .foregroundStyle(OrzMCTheme.Palette.metadata)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if let extra {
                extra
            }
            RemoteMetadataLine(items: tags)
            if let message, !message.isEmpty {
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(OrzMCTheme.Palette.metadata)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var disclosure: some View {
        if showsDisclosure {
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                // 箭头是**功能元素**（点击进下一页）：`.tertiary` 在面板上只有约 2.2:1，提到 secondary。
                .foregroundStyle(.secondary)
                .frame(width: 12)
                .accessibilityHidden(true)
        }
    }
}

extension ServerCard where Actions == EmptyView {
    init(
        name: String,
        statusTitle: String? = nil,
        statusStyle: OrzMCStatusStyle = .idle,
        address: String? = nil,
        tags: [String] = [],
        message: String? = nil,
        extra: AnyView? = nil,
        showsDisclosure: Bool = false,
        surface: ServerCardSurface = .panel,
        onTap: (() -> Void)? = nil,
        tapIdentifier: String? = nil,
        @ViewBuilder footer: @escaping () -> Footer
    ) {
        self.init(
            name: name,
            statusTitle: statusTitle,
            statusStyle: statusStyle,
            address: address,
            tags: tags,
            message: message,
            extra: extra,
            showsDisclosure: showsDisclosure,
            onTap: onTap,
            tapIdentifier: tapIdentifier,
            surface: surface,
            actions: { EmptyView() },
            footer: footer
        )
    }
}

extension ServerCard where Actions == EmptyView, Footer == EmptyView {
    init(
        name: String,
        statusTitle: String? = nil,
        statusStyle: OrzMCStatusStyle = .idle,
        address: String? = nil,
        tags: [String] = [],
        message: String? = nil,
        extra: AnyView? = nil,
        showsDisclosure: Bool = false,
        surface: ServerCardSurface = .panel,
        onTap: (() -> Void)? = nil,
        tapIdentifier: String? = nil
    ) {
        self.init(
            name: name,
            statusTitle: statusTitle,
            statusStyle: statusStyle,
            address: address,
            tags: tags,
            message: message,
            extra: extra,
            showsDisclosure: showsDisclosure,
            onTap: onTap,
            tapIdentifier: tapIdentifier,
            surface: surface,
            actions: { EmptyView() },
            footer: { EmptyView() }
        )
    }
}

// MARK: - 动作样式

/// 一组图标按钮：**图标 + 组间细分隔线**（与主窗口实例卡头 `FormSectionHeader` 同一套观感）。
///
/// 以前服务器卡片右侧是 `⋯ ⌄` 那种下拉胶囊：既不像按钮、又要点两级。
/// 现在能内联就内联（一眼看到能做哪些事），真的放不下再用 `ServerActionMenu` 收进 `⋯`。
struct ServerActionGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: 6) {
            content()
        }
    }
}

/// 组间分隔线（12pt 高，与主窗口一致）。
struct ServerActionDivider: View {
    var body: some View {
        Divider().frame(height: 12)
    }
}

/// 服务器卡片上的一个图标动作。
///
/// 规则（命中区 / 悬停底色 / disabled 变暗）都在设计系统的 `OrzMCActionButton` 里，
/// 主窗口实例卡头用的是同一个组件 —— 两个窗口的图标按钮不再各长一套。
struct ServerIconButton: View {
    let title: LocalizedStringKey
    let systemImage: String
    var tint: Color = OrzMCTheme.Palette.control
    var help: LocalizedStringKey? = nil
    var isEnabled = true
    var identifier: String? = nil
    let action: () -> Void

    var body: some View {
        OrzMCActionButton(
            title: title,
            systemImage: systemImage,
            tint: tint,
            help: help,
            isEnabled: isEnabled,
            identifier: identifier,
            action: action
        )
    }
}

/// `ServerCard` 的表面：顶层用面板，面板内部的行用 `.plain`。
///
/// 嵌套面板（账号卡里再套实例卡）会变成"玻璃套玻璃"，而且内外圆角相同、也不同心
/// （外层 14 / 内层 14 + 12pt 内边距）——2026-11-08 视觉评审的主要观感问题。
private struct ServerCardSurfaceModifier: ViewModifier {
    let surface: ServerCardSurface

    func body(content: Content) -> some View {
        switch surface {
        case .panel:
            // 内边距在 `body` 里（整卡点击层要盖住它）。
            content.orzMCPanel()
        case .plain:
            content
        }
    }
}

/// 放不下时才出现的 `⋯`（菜单项带文字标签，与内联图标一一对应）。
struct ServerActionMenu<Content: View>: View {
    var identifier: String? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        menu
            .menuStyle(.borderlessButton)
            .fixedSize()
    }

    @ViewBuilder
    private var menu: some View {
        if let identifier {
            base.accessibilityIdentifier(identifier)
        } else {
            base
        }
    }

    private var base: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(Text("More actions"))
    }
}
