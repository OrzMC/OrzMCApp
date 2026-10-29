//
//  ExarotonServerCard.swift
//  OrzMC
//

import OrzMCDesignSystem
import SwiftUI

/// 远程服务器**卡片**。
///
/// 之前这里是一行朴素的列表内容（标题 + 若干标签），和主窗口实例卡片（面板底 + 大圆角 +
/// 状态徽标 + 右侧动作）观感差得远，像两个 app。现在统一成同一套卡片语言：
/// 面板底、`OrzMCTheme` 间距、同一款状态徽标、整卡可点。
///
/// 列表行与详情页顶部共用这个组件，字段顺序固定：
/// `名称 + 状态徽标` → `软件 / 玩家` 标签 → `地址（可复制）` → `MOTD`。
struct ExarotonServerCard: View {
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
        HStack(alignment: .top, spacing: OrzMCTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
                header
                idLine
                tags
                addresses
                motd
            }

            Spacer(minLength: 0)

            if showsDisclosure {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
                    .accessibilityHidden(true)
            }
        }
    }

    private var header: some View {
        RemoteInstanceHeading(
            name: server.name ?? String(localized: "Server"),
            statusTitle: status?.localizedTitle,
            statusStyle: status?.statusStyle ?? .idle
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
        HStack(spacing: OrzMCTheme.Spacing.xs) {
            if let software = server.software {
                OrzMCTag("\(software.name ?? "—") \(software.version ?? "")")
            }
            if let players = server.players {
                OrzMCTag(String(localized: "\(Int(players.count ?? 0))/\(Int(players.max ?? 0)) players"))
            }
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
