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
                HStack(spacing: 10) {
                    Image(systemName: state.symbolName)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(version.id)
                            .lineLimit(1)

                        if let detail = rowDetail(for: version, state: state) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
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
        let installed = state.labels.joined(separator: ", ")
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
