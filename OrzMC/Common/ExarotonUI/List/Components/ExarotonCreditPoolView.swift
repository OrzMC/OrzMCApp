//
//  ExarotonCreditPoolView.swift
//  OrzMC
//
//  Created by joker on 2024/5/20.
//

import OrzMCDesignSystem
import SwiftUI

/// 额度池**行**（exaroton 特化）：名字 + id + 成员/服务器标签 + 额度。
///
/// 排版走 `RemoteInstanceRow`（与实例行、MCSM 实例行同一套骨架），
/// 这样"标题行 + 明细 + 右侧数值 + 箭头"在两家供应商、两种对象上都是同一个位置。
struct ExarotonCreditPoolView: View {
    let creditPool: ExarotonCreditPool

    var body: some View {
        RemoteInstanceRow(
            name: creditPool.name ?? String(localized: "Credit Pools"),
            showsDisclosure: true,
            details: {
                if let id = creditPool.id {
                    Text(id)
                        .font(OrzMCTheme.Typography.code)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                RemoteMetadataLine(items: [
                    String(localized: "\(creditPool.members ?? 0) members"),
                    String(localized: "\(creditPool.servers ?? 0) servers"),
                ])
            },
            trailing: {
                if let credits = creditPool.credits {
                    ExarotonCreditView(credits: credits)
                }
            }
        )
    }
}
