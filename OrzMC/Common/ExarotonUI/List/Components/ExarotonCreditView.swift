//
//  ExarotonCreditView.swift
//  OrzMC
//
//  Created by joker on 2024/5/20.
//

import OrzMCDesignSystem
import SwiftUI

struct ExarotonCreditView: View {
    enum Style {
        case inline
        case large
    }

    let credits: Double?
    var style: Style = .inline

    private var value: String {
        String(format: "%.2f", credits ?? 0)
    }

    var body: some View {
        switch style {
        case .inline:
            HStack(spacing: OrzMCTheme.Spacing.xs) {
                Image(systemName: "bubbles.and.sparkles.fill")
                    .foregroundStyle(OrzMCTheme.Palette.warning)
                Text(value)
                    .font(.callout.monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(value) credits"))
        case .large:
            VStack(spacing: OrzMCTheme.Spacing.sm) {
                Image(systemName: "bubbles.and.sparkles.fill")
                    .font(.system(.largeTitle, design: .default))
                    .foregroundStyle(OrzMCTheme.Palette.warning)
                Text(value)
                    .font(.title2.monospacedDigit().weight(.semibold))
                Text("credits")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text("\(value) credits"))
        }
    }
}

#Preview {
    HStack {
        ExarotonCreditView(credits: 12.345)
        ExarotonCreditView(credits: 12.345, style: .large)
            .frame(width: 160)
    }
    .padding()
}
