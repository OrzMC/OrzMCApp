//
//  ExarotonServerCard.swift
//  OrzMC
//

import OrzMCDesignSystem
import SwiftUI

/// 列表里的实例行：点进详情页。
///
/// 行本身走 `RemoteInstanceRow`（与 MCSM 实例行同一套骨架），**不再套第二层面板**：
/// 账号卡已经是一张面板，里面再套一层圆角面板在手机上像"卡片里的卡片"，
/// 也和 MCSM 那一段的平铺行不是一种观感。
struct ExarotonServerCardLink: View {
    @Environment(ExarotonServerModel.self) private var model
    let server: ExarotonServer

    var body: some View {
        NavigationLink {
            ExarotonServerDetail(server: server).environment(model)
        } label: {
            ExarotonServerCard(server: server, status: model.effectiveStatus(for: server), showsCopy: false)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("remote.serverCard")
    }
}

/// 额度池详情页里的实例行：那里是 `Form` 的 section，行背景是透明的，
/// 所以单独给一层面板，否则看起来像"没渲染完"。列表里**不用**这个。
struct ExarotonServerCardPanel: View {
    @Environment(ExarotonServerModel.self) private var model
    let server: ExarotonServer

    var body: some View {
        // `ServerCard` 自己就是一张面板，这里**不再**套第二层圆角（会变成"卡片里的卡片"）。
        ExarotonServerCard(server: server, status: model.effectiveStatus(for: server), showsCopy: false)
    }
}

/// 远程服务器**卡片**：走统一的 `ServerCard`（自建 / exaroton / MCSManager 三处同一套排布）。
///
/// 字段顺序固定：`名称 + 状态徽标` → `id` → `软件 / 玩家` 标签 → 地址（可复制）→ `MOTD`。
/// 列表行与详情页顶部共用这个组件：列表里地址是纯文本（整卡是按钮，塞复制按钮会互相吞点击），
/// 详情页里地址可复制。
struct ExarotonServerCard: View {
    let server: ExarotonServer
    /// 实际状态（WebSocket 推送优先）。列表/详情页传 `model.effectiveStatus(for:)`，
    /// 卡片本身不依赖 `ExarotonServerModel`，保持纯展示、可预览可单测。
    var status: ServerStatus?
    /// 列表行不显示 MOTD（太长）；详情页顶部的摘要显示。
    var showMotd = false
    /// 列表行右侧给一个指示箭头；详情页里不需要。
    var showsDisclosure = true
    /// 详情页里地址可复制；列表行整卡是按钮，不塞复制按钮（点击会互相吞掉）。
    var showsCopy = true

    var body: some View {
        ServerCard(
            name: server.name ?? String(localized: "Server"),
            statusTitle: status?.localizedTitle,
            statusStyle: status?.statusStyle ?? .idle,
            address: showsCopy ? nil : (server.staticAddress ?? server.dynamicAddress),
            tags: tags,
            message: showMotd ? plainMotd : nil,
            extra: showsCopy ? AnyView(addressRows) : nil,
            showsDisclosure: showsDisclosure
        )
    }

    /// 版本 / 玩家标签。
    private var tags: [String] {
        var tags: [String] = []
        if let software = server.software {
            tags.append("\(software.name ?? "—") \(software.version ?? "")")
        }
        if let players = server.players {
            tags.append(String(localized: "\(Int(players.count ?? 0))/\(Int(players.max ?? 0)) players"))
        }
        return tags
    }

    /// MOTD 去掉 `§x` 颜色码。
    private var plainMotd: String? {
        guard let motd = server.motd, !motd.isEmpty else { return nil }
        return motd.replacingOccurrences(
            of: "(?i)§[0-9a-fk-orx]",
            with: "",
            options: .regularExpression
        )
    }

    /// 详情页里的地址（可复制）。
    @ViewBuilder
    private var addressRows: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.hairline) {
            if let staticAddress = server.staticAddress {
                ExarotonCopyableText(staticAddress, canCopy: true)
            }
            if let dynamicAddress = server.dynamicAddress {
                ExarotonCopyableText(dynamicAddress, canCopy: true)
            }
        }
    }
}

#Preview {
    ExarotonServerCard(
        server: .init(
            id: "123124",
            name: "JokerHub",
            address: "https://paper.jokerhub.cn:25565",
            motd: "Welcom to JokerHub Server",
            status: .init(rawValue: ServerStatus.ONLINE.rawValue),
            host: "https://paper.jokerhub.cn",
            port: 25565,
            players: .init(max: 20, count: 1, list: ["joker"]),
            software: .init(id: "1", name: "paper", version: "1.20.6"),
            shared: false
        ),
        showMotd: true
    )
    .padding()
}
