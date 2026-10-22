//
//  ExarotonCreditPoolView.swift
//  OrzMC
//
//  Created by joker on 2024/5/20.
//

import OrzMCDesignSystem
import SwiftUI

struct ExarotonCreditPoolView: View {
    let creditPool: ExarotonCreditPool
    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
            HStack(alignment: .firstTextBaseline) {
                if let name = creditPool.name {
                    Text(name)
                        .font(.headline)
                        .lineLimit(1)
                }
                Spacer(minLength: OrzMCTheme.Spacing.sm)
                if let credits = creditPool.credits {
                    ExarotonCreditView(credits: credits)
                }
            }

            if let id = creditPool.id {
                Text(id)
                    .font(OrzMCTheme.Typography.code)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: OrzMCTheme.Spacing.xs) {
                OrzMCTag(String(localized: "\(creditPool.members ?? 0) members"))
                OrzMCTag(String(localized: "\(creditPool.servers ?? 0) servers"))
            }
        }
        .padding(.vertical, OrzMCTheme.Spacing.xs)
        .contentShape(Rectangle())
        .listRowSeparator(.hidden)
    }

}
