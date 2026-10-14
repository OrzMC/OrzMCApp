//
//  GameList.swift
//  OrzMC
//
//  Created by wangzhizhou on 2025/4/7.
//

import SwiftUI
import Game
import MojangAPI

struct GameList: View {
    @Binding var versions: [Version]
    @Binding var selectedVersion: Version?
    let isOnlyRelease: Bool
    let canUseShortcut: Bool
    var body: some View {
        ScrollViewReader { proxy in
            List(versions, selection: $selectedVersion) { version in
                HStack(spacing: 10) {
                    Image(systemName: installState(for: version).icon)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(version.id)
                            .lineLimit(1)

                        if let detail = rowDetail(for: version) {
                            Text(detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .tag(version)
                .help(rowHelp(for: version))
            }
            .listStyle(.sidebar)
            .disabled(!canUseShortcut)
            .onChange(of: selectedVersion) {
                guard let selectedVersionId = selectedVersion?.id
                else {
                    return
                }
                proxy.scrollTo(selectedVersionId)
            }
        }
    }
}

private extension GameList {
    func installState(for version: Version) -> (icon: String, labels: [String]) {
        var labels = [String]()
        if GamePlan.clientDir(version: version.id).isExist() {
            labels.append("Client")
        }
        if GamePlan.serverDir(version: version.id, type: .paper).isExist() {
            labels.append("Paper server")
        }
        if GamePlan.serverDir(version: version.id, type: .vanilla).isExist() {
            labels.append("Vanilla server")
        }

        if labels.contains("Client") {
            return ("macbook", labels)
        }
        if labels.contains("Paper server") || labels.contains("Vanilla server") {
            return ("xserve", labels)
        }
        return ("cube", labels)
    }

    func rowDetail(for version: Version) -> String? {
        let installed = installState(for: version).labels.joined(separator: ", ")
        if isOnlyRelease {
            return installed.isEmpty ? nil : installed
        }
        let buildType = version.buildType.rawValue.capitalized
        return installed.isEmpty ? buildType : "\(buildType) - \(installed)"
    }

    func rowHelp(for version: Version) -> String {
        rowDetail(for: version).map { "\(version.id), \($0)" } ?? version.id
    }
}

#Preview {
    @Previewable @State var versions = GameList.mockVersions
    @Previewable @State var selectedVersion: Version? = GameList.mockVersions.first
    GameList(
        versions: $versions,
        selectedVersion: $selectedVersion,
        isOnlyRelease: true,
        canUseShortcut: true
    )
}

extension GameList {
    static var mockVersions: [Version] = {
        // https://launchermeta.mojang.com/mc/game/version_manifest.json
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
          },
          {
            "id" : "1.21.5-rc1",
            "releaseTime" : "2025-03-20T13:45:48+00:00",
            "time" : "2025-03-25T11:02:08+00:00",
            "type" : "snapshot",
            "url" : "https://piston-meta.mojang.com/v1/packages/d5033f8da815671aafa4dd470becd452f856396c/1.21.5-rc1.json"
          },
          {
            "id" : "1.21.5-pre3",
            "releaseTime" : "2025-03-18T13:58:30+00:00",
            "time" : "2025-03-25T11:02:08+00:00",
            "type" : "snapshot",
            "url" : "https://piston-meta.mojang.com/v1/packages/fab86082576017501e5540baab3dcea93a82c153/1.21.5-pre3.json"
          },
          {
            "id" : "1.21.5-pre2",
            "releaseTime" : "2025-03-12T12:36:02+00:00",
            "time" : "2025-03-25T11:02:08+00:00",
            "type" : "snapshot",
            "url" : "https://piston-meta.mojang.com/v1/packages/743d9e145aaa4dc164a4fa0106b9f7e94c887cd0/1.21.5-pre2.json"
          },
          {
            "id" : "1.21.5-pre1",
            "releaseTime" : "2025-03-11T12:49:44+00:00",
            "time" : "2025-03-25T11:02:08+00:00",
            "type" : "snapshot",
            "url" : "https://piston-meta.mojang.com/v1/packages/bf48fdf5e407c9ebf6274ad7ebc01dab43208d6d/1.21.5-pre1.json"
          }
        ]
        """.data(using: .utf8)
        let jsonDecoder = JSONDecoder()
        guard let jsonData, let versions = try? jsonDecoder.decode([Version].self, from: jsonData)
        else {
            return []
        }
        return versions
    }()
}
