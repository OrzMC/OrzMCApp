//
//  ExarotonServerView.swift
//  OrzMC
//
//  Created by joker on 5/17/24.
//

import OrzMCDesignSystem
import SwiftUI

struct ExarotonServerView: View {
    let server: ExarotonServer
    var showStatus = true
    var showMotd = false
    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.hairline) {
                    Text(server.name ?? String(localized: "Server"))
                        .font(.headline)
                        .lineLimit(1)

                    HStack(spacing: OrzMCTheme.Spacing.xs) {
                        if let id = server.id {
                            Text(id)
                                .font(OrzMCTheme.Typography.code)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        if let software = server.software {
                            OrzMCTag("\(software.name ?? "—") \(software.version ?? "")")
                        }
                        if let players = server.players {
                            OrzMCTag(String(localized: "\(Int(players.count ?? 0))/\(Int(players.max ?? 0)) players"))
                        }
                    }
                }

                Spacer(minLength: OrzMCTheme.Spacing.sm)

                if showStatus, let status = server.serverStatus {
                    OrzMCStatusBadge(verbatim: status.localizedTitle, style: status.statusStyle)
                }
            }

            if showMotd, let motd = server.motd, !motd.isEmpty {
                Text(verbatim: motd.replacingOccurrences(of: "(?i)§[0-9a-fk-orx]", with: "", options: .regularExpression))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }

            if server.hasAddress {
                VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.hairline) {
                    if let staticAddress = server.staticAddress {
                        ExarotonCopyableText(staticAddress, canCopy: showMotd)
                    }
                    if let dynamicAddress = server.dynamicAddress {
                        ExarotonCopyableText(dynamicAddress, canCopy: showMotd)
                    }
                }
            }
        }
        .padding(.vertical, OrzMCTheme.Spacing.xs)
        .contentShape(Rectangle())
        .listRowSeparator(.hidden)
    }

}
#Preview {
    ExarotonServerView(
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
        ), showStatus: true
    )
    .padding()
}
