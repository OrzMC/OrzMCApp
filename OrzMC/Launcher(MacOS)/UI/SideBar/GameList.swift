//
//  GameList.swift
//  OrzMC
//
//  Created by wangzhizhou on 2025/4/7.
//

import SwiftUI
import Game
import MojangAPI
import OrzMCLauncher

/// 版本列表：**纯展示**。装了什么由 `VersionCatalogModel` 一次算好并传进来，
/// 视图 body 里不再做文件 IO（以前每行 3 次 stat、每次重绘都跑）。
///
/// 排版要点：
/// - 版本号用**等宽数字**，纵向对齐（`1.21.5` / `1.9` 不会错位）；
/// - 已装内容用**小徽标**（`Client` / `Paper` / …），比一长串句子更好扫；
/// - 未装任何东西的版本只显示版本号 + 类型，行高一致，列表不跳。
struct GameList: View {
    let versions: [Version]
    @Binding var selectedVersion: Version?
    let installStates: [String: VersionInstallState]
    let isOnlyRelease: Bool
    let canUseShortcut: Bool

    var body: some View {
        ScrollViewReader { proxy in
            List(versions, selection: $selectedVersion) { version in
                let state = installStates[version.id] ?? .none
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    // **别用 accentColor 画行内元素**：侧边栏选中行背景就是 accentColor，
                    // 同样的颜色会互相覆盖（标签直接看不见）。用语义色，选中时由系统自适应。
                    Image(systemName: state.symbolName)
                        .font(.callout)
                        .foregroundStyle(state.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.secondary))
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(version.id)
                                .font(.body.monospacedDigit())
                                .lineLimit(1)
                            if !isOnlyRelease {
                                Text(version.buildType.rawValue.capitalized)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 1)
                                    .background(Color.secondary.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                        }

                        if !state.isEmpty {
                            HStack(spacing: 4) {
                                ForEach(state.badges, id: \.self) { badge in
                                    Text(badge)
                                        .font(.caption2.weight(.medium))
                                        .foregroundStyle(.primary)
                                        .padding(.horizontal, 5)
                                        .padding(.vertical, 1)
                                        .background(Color.primary.opacity(0.10), in: Capsule())
                                }
                            }
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
                proxy.scrollTo(selectedVersionId)
            }
        }
    }
}

private extension GameList {
    func rowDetail(for version: Version, state: VersionInstallState) -> String? {
        let installed = state.badges.joined(separator: ", ")
        if isOnlyRelease {
            return installed.isEmpty ? nil : installed
        }
        let buildType = version.buildType.rawValue.capitalized
        return installed.isEmpty ? buildType : "\(buildType) - \(installed)"
    }

    func rowHelp(for version: Version, state: VersionInstallState) -> String {
        rowDetail(for: version, state: state).map { "\(version.id), \($0)" } ?? version.id
    }
}

#Preview {
    @Previewable @State var versions = GameList.mockVersions
    @Previewable @State var selectedVersion: Version? = GameList.mockVersions.first
    GameList(
        versions: versions,
        selectedVersion: $selectedVersion,
        installStates: [:],
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
