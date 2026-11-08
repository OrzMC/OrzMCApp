//
//  RemoteHostingSkeleton.swift
//  OrzMC
//
//  远程托管页（exaroton + MCSManager）**两家供应商共用的展示骨架**。
//
//  为什么要有这一层（2026-11-05）：两家的页面各写了一遍"标题行 + 账号面板 + 加载/空/错误态"，
//  结果同一个窗口里出现两套观感（exaroton 是"面板套面板"，MCSM 是平铺行；一边有重试按钮，
//  一边只有一行红字）。这里只抽**结构**：分组长什么样、账号卡长什么样、状态怎么显示；
//  供应商独有的能力（exaroton 的额度池/详情页/内存、MCSM 的控制台 sheet/强杀/面板编辑器）
//  继续留在各自界面里，不塞进骨架。
//
//  铁律（改这个文件前先读 `docs/app-ui-design.md`）：
//  · 分组顺序固定 `ProviderKind.allCases` = **exaroton → MCSManager**，不做筛选器；
//  · 状态徽章只走 `OrzMCStatusBadge`（经 `RemoteInstanceHeading`），这里不另画状态；
//  · 停止进度只走 `RemoteStopProgress`（调用方传进 `footer`），这里不判秒数；
//  · **不在容器上设 `accessibilityIdentifier`**（会覆盖子元素自己的 identifier）。
//

import OrzMCDesignSystem
import OrzMCRemoteHosting
import SwiftUI

// MARK: - 供应商分组

/// 一个来源的一组（标题行 + 账号/服务器卡片）。
///
/// 组内不再自带「添加账号」按钮：页顶只有一个入口（`ServersContentView.AddServerMenu`），
/// 先选服务器类型再填对应表单；一条记录都没有的来源**整组不渲染**（由页面级空态负责引导）。
///
/// 折叠由页面层决定（与主窗口实例栏同一套：`allExpanded` + 单栏覆盖）：
/// 折叠时**只保留标题行**，内容整段不渲染（模型轮询也就自然停在展开时）。
struct RemoteProviderSection<Content: View>: View {
    let name: String
    let systemImage: String
    let count: Int
    let identifier: String
    var isExpanded = true
    var onToggle: (() -> Void)? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
            RemoteProviderHeader(
                name: name,
                systemImage: systemImage,
                count: count,
                identifier: identifier,
                isExpanded: isExpanded,
                onToggle: onToggle
            )
            if isExpanded {
                content()
            }
        }
    }
}

// MARK: - 账号卡

/// 一个账号 / 一个 MCSManager 面板的卡片：统一的头部 + 内容 + 面板外观。
///
/// `content` 由供应商决定（exaroton：实例与额度池；MCSM：实例行），
/// 但"面板底 + 内边距 + 头部"这一层只有这里一份。
struct RemoteAccountCard<Actions: View, Content: View>: View {
    let name: String
    var subtitle: String? = nil
    let isLoading: Bool
    @ViewBuilder var actions: () -> Actions
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            RemoteAccountHeader(name: name, subtitle: subtitle, isLoading: isLoading, actions: actions)
            // 标题与内容之间一条细线：账号/面板现在只是**标签**，行才是内容
            // （2026-11-08 视觉评审：没有这条线时标题像"浮在卡片外"）。
            RemoteRowDivider()
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OrzMCTheme.Spacing.md)
        .orzMCPanel()
    }
}

/// 账号 / 面板的操作按钮组：两家供应商**同一套动作与顺序**（刷新 → 编辑 → 删除）。
///
/// 2026-11-07 改版（维护者要求对齐主窗口实例卡头的按钮风格）：
/// 以前是 `⋯ ⌄` 下拉胶囊 —— 既不像按钮、又要点两级；现在直接给**图标 + 组间细分隔线**
/// （`ServerIconButton` / `ServerActionDivider`，与 `FormSectionHeader` 同一套观感）。
/// 危险动作（删除）单独成组并用 `danger` 着色，避免和"刷新"混在一起。
struct RemoteAccountMenu: View {
    /// 拉一次最新数据（两家都支持；`nil` = 这家没有手动刷新）。
    var onRefresh: (() -> Void)? = nil
    let onEdit: () -> Void
    let onRemove: () -> Void
    /// 自动化锚点前缀（例如 MCSM 的 `mcsm.panel`）：实际锚点是 `<前缀>.refresh/.edit/.remove`。
    var identifier: String? = nil

    var body: some View {
        ServerActionGroup {
            if let onRefresh {
                icon("Refresh", "arrow.clockwise", key: .refresh, help: "Reload this account's servers") {
                    onRefresh()
                }
                ServerActionDivider()
            }
            icon("Edit Account", "slider.horizontal.3", key: .edit, help: "Edit this account") {
                onEdit()
            }
            ServerActionDivider()
            // 危险色**不常驻**：图标红着会一直抢注意力，也和主窗口的中性删除图标不一致。
            // 真正的红色留给确认框里的 destructive 按钮。
            icon("Remove Account", "trash", key: .remove, help: "Remove this account") {
                onRemove()
            }
        }
    }

    private enum Part: String { case refresh, edit, remove }

    private func icon(
        _ title: LocalizedStringKey,
        _ systemImage: String,
        key: Part,
        help: LocalizedStringKey,
        tint: Color = OrzMCTheme.Palette.control,
        action: @escaping () -> Void
    ) -> some View {
        ServerIconButton(
            title: title,
            systemImage: systemImage,
            tint: tint,
            help: help,
            identifier: identifier.map { "\($0)Action.\(key.rawValue)" },
            action: action
        )
    }
}

// MARK: - 账号内的状态（加载 / 空 / 错误）

/// 账号内的一行加载态。
///
/// 以前 exaroton 是 `ProgressView("Loading remote servers…")`（占一整行、文案还长），
/// MCSM 是 `Text("Loading…")`。现在统一成"小转圈 + 一行小字"。
struct RemoteInlineLoading: View {
    var title: String = String(localized: "Loading…")

    var body: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 账号内的一行空态（这家账号/面板下没有实例）。
struct RemoteInlineEmpty: View {
    var title: String = String(localized: "No instances")

    var body: some View {
        Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// 账号内的错误态：统一走 `OrzMCBanner`（图标 + 可选中文本），需要时给「重试」。
///
/// 以前 exaroton 用横幅但 MCSM 只有一行红字、且没有重试 —— 面板抽风时用户只能杀进程重开。
struct RemoteInlineError: View {
    let message: String
    /// 重试动作（`nil` = 不给按钮，例如动作类错误）。
    var retry: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            OrzMCBanner(verbatim: message, role: .error)
            if let retry {
                Button(String(localized: "Retry"), action: retry)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 面板卡内部行与行之间的细线。
///
/// 平铺行（`.plain`）自己没有面板，靠这条线表达"这是同一张卡里的两行"（系统分组列表的做法）。
struct RemoteRowDivider: View {
    var body: some View {
        Divider().opacity(0.5)
    }
}

/// 一行**元信息**（版本 / 玩家 / 延迟 / 成员数…）：纯文本 + `·` 分隔。
///
/// 以前这里是描边胶囊（`OrzMCTag`）：和状态徽章同形，一张卡里 3 个胶囊 + 1 个徽章，
/// 看起来像 4 个可点的过滤器。元信息是**内容**不是控件（HIG Layout：控件与内容要有区别）；
/// 纯文本还能在 iPhone 窄屏 / 大字号下自然换行。
struct RemoteMetadataLine: View {
    let items: [String]

    var body: some View {
        if !items.isEmpty {
            Text(verbatim: items.joined(separator: " · "))
                .font(.caption)
                .foregroundStyle(OrzMCTheme.Palette.metadata)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// 账号卡内的二级小节标题（例如 exaroton 的「额度池」）。
struct RemoteSubsectionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: systemImage).accessibilityHidden(true)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
}
