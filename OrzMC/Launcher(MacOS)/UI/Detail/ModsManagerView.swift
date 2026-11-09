//
//  ModsManagerView.swift
//  OrzMC
//
//  「模组」面板：Fabric / Forge 服务端的 `mods/` 入口。
//
//  这一版只做**本地清单**（列出已装的 jar + 打开目录 + 重新扫描）。
//  搜索 / 安装 / 更新 / 卸载（Modrinth、Hangar 渠道）是下一轮的事，
//  所以这里刻意不提供"安装"按钮，避免做出半成品交互。
//

import JokerKits
import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 要打开哪个实例的模组面板（版本 + 核心类型决定 `mods/` 路径）。
struct ModsSheetTarget: Identifiable {
    let versionId: String
    let software: SettingsModel.ServerSoftware

    var id: String { "\(versionId)-\(software.rawValue)" }
}

struct ModsManagerView: View {
    let target: ModsSheetTarget

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var manager = ModsManagerModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                Divider()
                footer
            }
            .navigationTitle("Mods — \(target.versionId)")
            .searchable(text: $manager.searchText, placement: .toolbar, prompt: "Search mods")
            .toolbar {
                ToolbarItemGroup {
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        manager.refresh()
                    }
                    .help("Rescan the mods folder")
                    .accessibilityIdentifier("mods.refresh")

                    Button("Open Folder", systemImage: "folder") {
                        openFolder()
                    }
                    .help("Open the mods folder in Finder")
                    .accessibilityIdentifier("mods.openFolder")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 440)
        .task {
            manager.bind(
                versionId: target.versionId,
                software: target.software,
                rootDir: app.settings.rootDir
            )
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private var content: some View {
        if manager.mods.isEmpty {
            VStack(spacing: OrzMCTheme.Spacing.md) {
                EmptyContentView(
                    ContentState(
                        title: String(localized: "No mods installed"),
                        message: String(
                            localized: "Put Fabric/Forge mod jars into the mods folder. Installing and updating mods from Modrinth comes in a later update."
                        ),
                        systemImage: "shippingbox"
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Button("Open Mods Folder", systemImage: "folder") {
                    openFolder()
                }
            }
            .padding(OrzMCTheme.Spacing.lg)
        } else if manager.filtered.isEmpty {
            EmptyContentView(
                ContentState(
                    title: String(localized: "No matching mods"),
                    systemImage: "magnifyingglass"
                )
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(manager.filtered) { mod in
                HStack(spacing: OrzMCTheme.Spacing.sm) {
                    Image(systemName: "shippingbox")
                        .foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: mod.fileName)
                        if let version = mod.version {
                            Text(verbatim: version)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)
        }
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
            Text(
                "Only jars already in the mods folder are listed. Searching, installing, updating and removing mods (Modrinth / Hangar) comes in a later update."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: OrzMCTheme.Spacing.sm)

            Text(verbatim: manager.modsDirectory)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(manager.modsDirectory)
        }
        .padding(OrzMCTheme.Spacing.md)
    }

    // MARK: - 行为

    /// 打开 `mods/`：目录不存在就先建（Fabric/Forge 尚未启动过时也会缺）。
    private func openFolder() {
        guard !manager.modsDirectory.isEmpty else { return }
        let fm = FileManager.default
        if !fm.fileExists(atPath: manager.modsDirectory) {
            try? fm.createDirectory(atPath: manager.modsDirectory, withIntermediateDirectories: true)
        }
        do {
            try Shell.runCommand(with: ["open", manager.modsDirectory])
        } catch {
            app.error = LauncherError(
                code: "E_IO",
                message: String(localized: "Could not open the folder. \(error.localizedDescription)")
            )
        }
    }
}
