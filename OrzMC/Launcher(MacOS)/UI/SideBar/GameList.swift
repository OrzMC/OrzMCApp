//
//  GameList.swift
//  OrzMC
//
//  Created by wangzhizhou on 2025/4/7.
//

import Game
import MojangAPI
import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 版本列表：**纯展示**。装了什么由 `VersionCatalogModel` 一次算好并传进来，
/// 视图 body 里不做文件 IO。
///
/// 行设计（2026-10-22 方案 B）：
/// - 第一行：版本号（等宽数字）+「最新」徽标；
/// - 第二行：**发布日期（今天 / 昨天 / N 天前 / 绝对日期）· 已装内容（最多两项 + N）**；
/// - 行首图标表示安装状态；悬停提示给完整信息（含类型与全部已装项）。
struct GameList: View {
    let versions: [Version]
    @Binding var selectedVersion: Version?
    let installStates: [String: VersionInstallState]
    /// 清单里的「最新正式版 / 最新快照」id。
    let latestReleaseId: String?
    let latestSnapshotId: String?
    let isOnlyRelease: Bool
    let canUseShortcut: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// 列表底层滚动（跳到首/末项时用）：`scrollTo` 对懒加载 List 只能落到"估算位置"。
    @State private var scrollController = VersionListScrollController()

    var body: some View {
        ScrollViewReader { proxy in
            List(versions, selection: $selectedVersion) { version in
                let state = installStates[version.id] ?? .none
                HStack(alignment: .center, spacing: 8) {
                    // **别用 accentColor 画行内元素**：侧边栏选中行背景就是 accentColor。
                    Image(systemName: state.symbolName)
                        .font(.callout)
                        .foregroundStyle(state.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        .frame(width: 18)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(version.id)
                                .font(OrzMCTheme.Typography.numeric)
                                .lineLimit(1)
                            if let badge = latestBadge(for: version) {
                                OrzMCTag(badge, tint: OrzMCTheme.Palette.accent)
                            }
                        }
                        // 第二行：日期 · 已装内容；两者都没有就不占位（更紧凑）。
                        if let detail = detailText(for: version, state: state) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 2)
                .tag(version)
                .help(rowHelp(for: version, state: state))
            }
            .listStyle(.sidebar)
            .disabled(!canUseShortcut)
            .onChange(of: selectedVersion) {
                guard let selectedVersionId = selectedVersion?.id else { return }
                // 首/末项：直接滚到列表真正的顶/底（含末尾留白）；
                // 中间项：`scrollTo` 的最小滚动即可。
                if selectedVersionId == versions.first?.id {
                    scrollController.scrollToTop()
                } else if selectedVersionId == versions.last?.id {
                    scrollController.scrollToBottom()
                } else {
                    proxy.scrollTo(selectedVersionId)
                }
            }
            .background(VersionListScrollProbe(controller: scrollController))
        }
    }
}

extension GameList {
    /// 最新正式版 / 最新快照的徽标。
    func latestBadge(for version: Version) -> LocalizedStringKey? {
        if version.id == latestReleaseId { return "Latest" }
        if version.id == latestSnapshotId { return "Latest snapshot" }
        return nil
    }

    /// 副标题：`发布日期 · 已装内容（最多两项 + N）`。
    func detailText(for version: Version, state: VersionInstallState) -> String? {
        var parts: [String] = []
        if let released = VersionDateText.parse(version.releaseTime) {
            parts.append(Self.dayText(VersionDateText.day(for: released)))
        }
        let badges = state.badges.map(Self.localizedBadge)
        var installed = Array(badges.prefix(2))
        // 只有 "Client" 时前面会多出一个「N 天前」；徽标超两项就给一句人话，
        // 而不是 `+2`（以前 "+N" 看不出是"还有 2 项"）。
        if badges.count > 2 {
            installed.append(String(localized: "\(badges.count - 2) more"))
        }
        parts.append(contentsOf: installed)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// 安装徽标 → 界面文案。
    ///
    /// `VersionInstallState.badges` 是**平台无关层**（`Sources/OrzMCLauncher`）产出的原始字符串，
    /// 那里不做本地化（它对 CLI 也说同一套话）。`Client` 是通用词，必须按语言翻；
    /// `Paper` / `Vanilla` / `Fabric` / `Forge` 是产品名，保持原样。
    static func localizedBadge(_ badge: String) -> String {
        badge == "Client" ? String(localized: "Client") : badge
    }

    /// 日期判定 → 本地化文案（`Sources/*` 不做本地化，见 `VersionDateText`）。
    static func dayText(_ day: VersionDateText.Day) -> String {
        switch day {
        case .today: return String(localized: "Today")
        case .yesterday: return String(localized: "Yesterday")
        case .daysAgo(let count): return String(localized: "\(count) days ago")
        case .absolute(let text): return text
        }
    }

    /// 悬停提示：版本 + 类型 + 全部已装内容。
    func rowHelp(for version: Version, state: VersionInstallState) -> String {
        var parts = [version.id]
        if !isOnlyRelease { parts.append(version.localizedBuildTypeTitle) }
        if state.hasClient { parts.append(String(localized: "Client")) }
        // `servers` 里是小写标识（paper/…），展示用首字母大写 + 本地化的「服务端」后缀。
        for server in state.servers {
            parts.append(String(localized: "\(server.capitalized) server"))
        }
        return parts.joined(separator: "·")
    }
}

#Preview {
    @Previewable @State var versions = GameList.mockVersions
    @Previewable @State var selectedVersion: Version? = GameList.mockVersions.first
    GameList(
        versions: versions,
        selectedVersion: $selectedVersion,
        installStates: [:],
        latestReleaseId: "1.21.5",
        latestSnapshotId: nil,
        isOnlyRelease: true,
        canUseShortcut: true
    )
}

extension GameList {
    static var mockVersions: [Version] = {
        let jsonData = """
        [
          {
            "id" : "1.21.5",
            "releaseTime" : "2025-03-25T12:14:58+00:00",
            "time" : "2025-03-25T12:24:50+00:00",
            "type" : "release",
            "url" : "https://piston-meta.mojang.com/v1/packages/09fe09042d1767d677649d1e4a9d26ce3b462ebb/1.21.5.json"
          },
          {
            "id" : "1.21.5-rc2",
            "releaseTime" : "2025-03-24T13:07:03+00:00",
            "time" : "2025-03-25T11:02:08+00:00",
            "type" : "snapshot",
            "url" : "https://piston-meta.mojang.com/v1/packages/fc4da084369428c8dda5f4fc0dcac6ce9c260505/1.21.5-rc2.json"
          }
        ]
        """.data(using: .utf8)!
        return (try? JSONDecoder().decode([Version].self, from: jsonData)) ?? []
    }()
}
