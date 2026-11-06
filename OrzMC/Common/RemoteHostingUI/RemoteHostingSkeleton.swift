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

/// 一家供应商的一组（标题行 + 账号卡）。
///
/// 组内不再自带「添加账号」按钮：页顶只有一个入口（`RemoteAddProviderMenu`），
/// 先选供应商再填对应表单；一个账号都没有的供应商**整组不渲染**（由页面级空态负责引导）。
struct RemoteProviderSection<Content: View>: View {
    let name: String
    let systemImage: String
    let count: Int
    let identifier: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
            RemoteProviderHeader(
                name: name,
                systemImage: systemImage,
                count: count,
                identifier: identifier
            )
            content()
        }
    }
}

/// 页顶**唯一**的添加入口：先选供应商，再填该供应商的表单。
///
/// 以前每个供应商分组各有一个「添加账号」，空页上两个按钮长得一样、用户要先分清自己加的是哪家；
/// 现在统一成一个菜单：选哪家就弹哪家的表单（exaroton：账号 + TOKEN；MCSManager：地址 + API Key）。
struct RemoteAddProviderMenu: View {
    let onSelect: (ProviderKind) -> Void

    var body: some View {
        Menu {
            Button {
                onSelect(.exaroton)
            } label: {
                Label {
                    Text(verbatim: "exaroton")
                } icon: {
                    Image(systemName: "cloud")
                }
            }
            .accessibilityIdentifier("remote.addProvider.exaroton")

            Button {
                onSelect(.mcsmanager)
            } label: {
                Label {
                    Text(verbatim: "MCSManager")
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                }
            }
            .accessibilityIdentifier("remote.addProvider.mcsmanager")
        } label: {
            Label(String(localized: "Add Account"), systemImage: "plus.circle").font(.callout)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("remote.addProvider")
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
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OrzMCTheme.Spacing.md)
        .orzMCPanel()
    }
}

/// 账号 / 面板的操作菜单：两家供应商**同一套动作与顺序**（刷新 → 编辑 → 删除）。
///
/// 以前 MCSM 没有「刷新」、exaroton 没有分隔线，用户在两段之间要重新学一遍菜单。
struct RemoteAccountMenu: View {
    /// 拉一次最新数据（两家都支持；`nil` = 这家没有手动刷新）。
    var onRefresh: (() -> Void)? = nil
    let onEdit: () -> Void
    let onRemove: () -> Void
    /// 用例/自动化锚点（**只给必要的那一家**：MCSM 面板菜单有 `mcsm.panelMenu`）。
    var identifier: String? = nil

    var body: some View {
        if let identifier {
            menu.accessibilityIdentifier(identifier)
        } else {
            menu
        }
    }

    private var menu: some View {
        Menu {
            if let onRefresh {
                Button {
                    onRefresh()
                } label: {
                    Label(String(localized: "Refresh"), systemImage: "arrow.clockwise")
                }
                Divider()
            }
            Button {
                onEdit()
            } label: {
                Label(String(localized: "Edit Account"), systemImage: "slider.horizontal.3")
            }
            Divider()
            Button(role: .destructive) {
                onRemove()
            } label: {
                Label(String(localized: "Remove Account"), systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .accessibilityLabel(Text("Account actions", comment: "Account menu accessibility label"))
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
