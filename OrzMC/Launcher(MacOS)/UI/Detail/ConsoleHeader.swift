//
//  ConsoleHeader.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 控制台头部：状态徽标 + 实例名 + 进行态标签 + Follow 开关 + 行数。
struct ConsoleHeader: View {
    let title: String
    /// 当前状态（Running / Stopped / Game running …）。
    let statusKey: LocalizedStringKey
    let isAttached: Bool
    /// 生命周期进行态（Starting… / Stopping…），来自 `AppModel.activity`。
    let statusTag: String?
    let totalLines: Int
    /// 搜索时的可见行数（`nil` = 未搜索）。
    let visibleLines: Int?
    @Binding var follow: ConsoleFollowState
    /// 打开 Follow（= 退出搜索 + 回到最新）。
    let onRequestFollow: () -> Void

    private var followToggle: Binding<Bool> {
        Binding(
            get: { follow.shouldScrollToLatest },
            set: { wantsFollow in
                if wantsFollow {
                    onRequestFollow()
                } else {
                    follow.suspendFollowing()
                }
            }
        )
    }

    var body: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            OrzMCStatusBadge(statusKey, style: isAttached ? .running : .idle)

            Text(verbatim: title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            if let statusTag {
                OrzMCTag(statusTag, tint: OrzMCTheme.Palette.warning)
            }

            Spacer()

            Toggle("Follow", isOn: followToggle)
                .toggleStyle(.button)
                .controlSize(.small)
                .help("Scroll to the newest line as output arrives")

            Group {
                if let visibleLines {
                    Text("\(visibleLines) / \(totalLines) lines")
                } else {
                    Text("\(totalLines) lines")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, OrzMCTheme.Spacing.md)
        .padding(.vertical, OrzMCTheme.Spacing.sm)
    }
}
