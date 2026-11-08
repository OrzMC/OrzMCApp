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
struct SelfHostedServersSection: View {
    let model: SelfHostedServersModel

    private var servers: [SelfHostedServerProfile] { model.profiles.servers }

    var body: some View {
        RemoteProviderSection(
            name: String(localized: "Self-hosted"),
            systemImage: "server.rack",
            count: servers.count,
            identifier: "selfHosted.section"
        ) {
            ForEach(servers) { profile in
                NavigationLink {
                    SelfHostedServerDetailView(profileID: profile.id, model: model)
                } label: {
                    SelfHostedServerCard(
                        profile: profile,
                        status: model.status(for: profile.id),
                        statusError: model.statusErrorText(for: profile.id),
                        playersText: model.playersText(for: profile.id),
                        lastUpdated: model.lastUpdated(for: profile.id),
                        isProbing: model.isProbingAll
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("selfHosted.serverCard")
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

    private var statusTitle: String {
        if isProbing, status == nil { return String(localized: "Checking…") }
        return status != nil ? String(localized: "Online") : String(localized: "Offline")
    }

    private var statusStyle: OrzMCStatusStyle {
        if isProbing, status == nil { return .busy }
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
            showsDisclosure: true
        ) {
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
                .foregroundStyle(.tertiary)
                .frame(height: 14, alignment: .leading)
        }
    }
}

#Preview {
    ServersContentView()
        .frame(width: 900, height: 620)
}
