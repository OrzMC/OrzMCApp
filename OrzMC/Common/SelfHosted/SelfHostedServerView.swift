//
//  SelfHostedServerView.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCLauncher
import OrzMCProtocol
import SwiftUI

/// **自建服务器**分组（`ServersContentView` 里的第一组）：标题行 + 服务器信息卡片列表。
///
/// 2026-11-08 起自建与远程托管合并在同一页（一个列表、页顶一个「添加服务器」菜单），
/// 所以这里不再自己持模型、不再有页顶按钮和空态页：**模型由页面层持有**（添加/删除后
/// 卡片与状态要一起刷新），空态也由页面层统一给（一个来源一条记录都没有时整组不渲染）。
/// RCON / 玩家 / 控制台这些**与某台服务器强相关**的内容仍在详情页（`SelfHostedServerDetailView`）。
///
/// 卡片的动作（刷新 / 配置 / 删除）与 exaroton 账号卡、MCSM 面板卡**同一套** `ServerActionGroup`：
/// 图标 + 组间细分隔线，危险动作单独成组并着色。以前这些只散落在详情页工具栏与设置表单里，
/// 列表上看不出"这张卡能做什么"（2026-11-08 维护者反馈）。
struct SelfHostedServersSection: View {
    let model: SelfHostedServersModel
    /// 分组是否展开（折叠时只保留标题行，与远程分组同一套）。
    var isExpanded = true
    var onToggle: (() -> Void)? = nil
    /// 点卡片：由页面层推进导航（这样卡片里的动作按钮才点得到，不会被 `NavigationLink` 吞掉）。
    let onOpen: (SelfHostedServerProfile) -> Void
    let onEdit: (SelfHostedServerProfile) -> Void
    let onDelete: (SelfHostedServerProfile) -> Void

    private var servers: [SelfHostedServerProfile] { model.profiles.servers }

    var body: some View {
        RemoteProviderSection(
            name: String(localized: "Self-hosted"),
            systemImage: "server.rack",
            count: servers.count,
            identifier: "selfHosted.section",
            isExpanded: isExpanded,
            onToggle: onToggle
        ) {
            ForEach(servers) { profile in
                SelfHostedServerCard(
                    profile: profile,
                    status: model.status(for: profile.id),
                    statusError: model.statusErrorText(for: profile.id),
                    playersText: model.playersText(for: profile.id),
                    lastUpdated: model.lastUpdated(for: profile.id),
                    isProbing: model.isProbingAll,
                    isRefreshing: model.isRefreshing(profile.id),
                    onOpen: { onOpen(profile) },
                    onRefresh: { Task { await model.refreshStatus(for: profile.id) } },
                    onEdit: { onEdit(profile) },
                    onRemove: { onDelete(profile) }
                )
            }
        }
    }
}

// MARK: - 卡片

/// 一台自建服务器的**信息卡片**。
///
/// 走统一的 `ServerCard`（自建 / exaroton / MCSManager 三处同一套排布与动作样式），
/// 字段顺序：`名称 + 状态徽标` → `地址` → `版本/玩家/延迟` 标签 → `MOTD` → 更新时间。
struct SelfHostedServerCard: View {
    let profile: SelfHostedServerProfile
    let status: MCStatusSummary?
    let statusError: String?
    let playersText: String?
    let lastUpdated: Date?
    /// 列表正在批量探测（还没拿到第一份结果时显示"检查中…"）。
    var isProbing = false
    /// 这一台正在单台刷新。
    var isRefreshing = false
    /// 点卡片本体（名称 / 明细那块按钮）时进详情页。
    var onOpen: (() -> Void)? = nil
    var onRefresh: (() -> Void)? = nil
    var onEdit: (() -> Void)? = nil
    var onRemove: (() -> Void)? = nil

    private var isChecking: Bool { (isProbing || isRefreshing) && status == nil }

    private var statusTitle: String {
        if isChecking { return String(localized: "Checking…") }
        return status != nil ? String(localized: "Online") : String(localized: "Offline")
    }

    private var statusStyle: OrzMCStatusStyle {
        if isChecking { return .busy }
        return status != nil ? .running : .idle
    }

    private var tags: [String] {
        var tags: [String] = []
        if let version = status?.versionName { tags.append(version) }
        if let playersText { tags.append(playersText) }
        if let latency = status?.latencyMilliseconds, latency > 0 {
            tags.append(String(localized: "\(latency) ms"))
        }
        return tags
    }

    var body: some View {
        ServerCard(
            name: profile.displayName,
            statusTitle: statusTitle,
            statusStyle: statusStyle,
            address: profile.address,
            tags: tags,
            message: status?.motd,
            showsDisclosure: true,
            onTap: onOpen,
            tapIdentifier: "selfHosted.serverCard",
            actions: { actions },
            footer: { footer }
        )
    }

    /// 与 `RemoteAccountMenu` / MCSM 实例动作同一套：刷新 ｜ 配置 ｜ 删除（危险动作单独成组）。
    @ViewBuilder
    private var actions: some View {
        ServerActionGroup {
            if isRefreshing {
                ProgressView().controlSize(.mini)
            }
            ServerIconButton(
                title: "Refresh",
                systemImage: "arrow.clockwise",
                help: "Check the server status now",
                isEnabled: profile.isConfigured && !isRefreshing,
                identifier: "selfHosted.action.refresh"
            ) {
                onRefresh?()
            }
            ServerActionDivider()
            ServerIconButton(
                title: "Settings",
                systemImage: "slider.horizontal.3",
                help: "Server address, port and RCON",
                identifier: "selfHosted.action.edit"
            ) {
                onEdit?()
            }
            ServerActionDivider()
            ServerIconButton(
                title: "Delete",
                systemImage: "trash",
                help: "Removes the address, the saved RCON password and the console history (asks for confirmation)",
                identifier: "selfHosted.action.remove"
            ) {
                onRemove?()
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if let statusError {
            Text(verbatim: statusError)
                .font(.caption)
                .foregroundStyle(OrzMCTheme.Palette.danger)
                .lineLimit(2)
        }
        // 这一行始终存在（没有更新时间就占位），否则首次加载完成后卡片会突然长高一行。
        Text(lastUpdated.map {
            String(localized: "Updated \($0.formatted(date: .omitted, time: .standard))")
        } ?? " ")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(height: 14, alignment: .leading)
    }
}

#Preview {
    ServersContentView()
        .frame(width: 900, height: 620)
}
