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
        ExarotonServerCard(server: server, status: model.effectiveStatus(for: server), showsCopy: false)
            .padding(OrzMCTheme.Spacing.sm)
            .orzMCPanel()
    }
}

/// 远程服务器**卡片**。
///
/// 之前这里是一行朴素的列表内容（标题 + 若干标签），和主窗口实例卡片（面板底 + 大圆角 +
/// 状态徽标 + 右侧动作）观感差得远，像两个 app。现在统一成同一套卡片语言：
/// 面板底、`OrzMCTheme` 间距、同一款状态徽标、整卡可点。
///
/// 列表行与详情页顶部共用这个组件，字段顺序固定：
/// `名称 + 状态徽标` → `软件 / 玩家` 标签 → `地址（可复制）` → `MOTD`。
struct ExarotonServerCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let server: ExarotonServer
    /// 实际状态（WebSocket 推送优先）。列表/详情页传 `model.effectiveStatus(for:)`，
    /// 卡片本身不依赖 `ExarotonServerModel`，保持纯展示、可预览可单测。
    var status: ServerStatus?
    /// 列表行不显示 MOTD（太长）；详情页顶部的摘要显示三行。
    var showMotd = false
    /// 列表行右侧给一个指示箭头；详情页里不需要。
    var showsDisclosure = true
    /// 地址旁是否给"复制"按钮。
    ///
    /// 列表里整卡是一个按钮（点进详情），把复制按钮塞进按钮标签里会互相吞点击，
    /// 所以列表行不显示复制按钮——详情页里地址同样是可复制的。
    var showsCopy = true

    var body: some View {
        RemoteInstanceRow(
            name: server.name ?? String(localized: "Server"),
            statusTitle: status?.localizedTitle,
            statusStyle: status?.statusStyle ?? .idle,
            showsDisclosure: showsDisclosure,
            details: {
                idLine
                tags
                addresses
                motd
            }
        )
    }

    /// 服务器 id **单独一行**：和版本/玩家标签挤在一行时，窄屏上必然被截断（真机反馈）。
    @ViewBuilder
    private var idLine: some View {
        if let id = server.id {
            Text(id)
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)      // id 只是"对上号"用的，不该抢地址的注意力
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }

    private var tags: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
                    if let software = server.software {
                        Text(verbatim: "\(software.name ?? "—") \(software.version ?? "")")
                    }
                    if let players = server.players {
                        Text("\(Int(players.count ?? 0))/\(Int(players.max ?? 0)) players")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: OrzMCTheme.Spacing.xs) { tagContents }
                    VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) { tagContents }
                }
            }
        }
    }

    @ViewBuilder private var tagContents: some View {
        if let software = server.software {
            OrzMCTag("\(software.name ?? "—") \(software.version ?? "")")
        }
        if let players = server.players {
            OrzMCTag(String(localized: "\(Int(players.count ?? 0))/\(Int(players.max ?? 0)) players"))
        }
    }

    @ViewBuilder
    private var addresses: some View {
        if server.hasAddress {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.hairline) {
                if let staticAddress = server.staticAddress {
                    ExarotonCopyableText(staticAddress, canCopy: showsCopy)
                }
                if let dynamicAddress = server.dynamicAddress {
                    ExarotonCopyableText(dynamicAddress, canCopy: showsCopy)
                }
            }
        }
    }

    @ViewBuilder
    private var motd: some View {
        if showMotd, let motd = server.motd, !motd.isEmpty {
            Text(verbatim: motd.replacingOccurrences(
                of: "(?i)§[0-9a-fk-orx]",
                with: "",
                options: .regularExpression
            ))
            .font(.callout)
            .foregroundStyle(.secondary)
            .lineLimit(3)
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
