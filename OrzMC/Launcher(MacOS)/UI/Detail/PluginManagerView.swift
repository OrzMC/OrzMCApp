//
//  PluginManagerView.swift
//  OrzMC
//
//  插件管理面板：已装插件 + Hangar 目录 → 安装 / 更新。
//

import SwiftUI
import Game
import OrzMCDesignSystem
import OrzMCLauncher

/// 插件管理：从**Plugins 目录条目**进入（不再是独立目录项）。
///
/// 下载目标由引擎决定（`PluginInstaller`）：
/// - 没装过 → `plugins/`；
/// - 已装（更新）→ `plugins/update/`，服务端下次启动时应用。
struct PluginManagerView: View {

    let versionId: String

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var manager = PluginManagerModel()
    @State private var showHangarCatalog = true

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                content
                Divider()
                footer
            }
            .navigationTitle("Plugins — \(versionId)")
            // 系统搜索框（工具栏），不再自己拼 TextField。
            .searchable(text: $manager.searchText, placement: .toolbar, prompt: "Search plugins")
            .toolbar {
                ToolbarItemGroup {
                    if manager.isLoadingCatalog || manager.isCheckingUpdates {
                        ProgressView()
                            .controlSize(.small)
                    }

                    Toggle(isOn: $showHangarCatalog) {
                        Label("Catalog", systemImage: "list.bullet")
                    }
                    .toggleStyle(.button)
                    .help("Show plugins from the Hangar catalog (off = installed only)")

                    Button("Check Updates", systemImage: "arrow.triangle.2.circlepath") {
                        Task {
                            await manager.loadCatalogIfNeeded()
                            await manager.checkUpdates()
                        }
                    }
                    .disabled(manager.isLoadingCatalog || manager.isCheckingUpdates)
                    .help("Check installed plugins for newer Hangar versions")

                    Button("Update All", systemImage: "arrow.down.circle") {
                        Task { await manager.updateAll() }
                    }
                    .disabled(manager.updateCount == 0 || manager.busyPlugin != nil)
                    .help("Download updates to plugins/update/ — applied on next restart")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .task {
            manager.bind(versionId: versionId, rootDir: app.settings.rootDir)
            await manager.loadCatalogIfNeeded()
        }
    }

    private var content: some View {
        Group {
            if visibleRows.isEmpty {
                ContentUnavailableView(
                    "No plugins",
                    systemImage: "puzzlepiece.extension",
                    description: Text("Install a plugin from Hangar, or drop a jar into plugins/ and refresh.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    let installed = visibleRows.filter(\.isInstalled)
                    let available = visibleRows.filter { !$0.isInstalled }
                    if !installed.isEmpty {
                        Section("Installed (\(manager.installedJars.count))") {
                            ForEach(installed) { row in
                                rowView(row)
                            }
                        }
                    }
                    if !available.isEmpty {
                        Section("Available") {
                            ForEach(available) { row in
                                rowView(row)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var visibleRows: [PluginManagerModel.Row] {
        let rows = manager.filteredRows
        return showHangarCatalog ? rows : rows.filter(\.isInstalled)
    }

    private func rowView(_ row: PluginManagerModel.Row) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(row.name).font(.body.weight(.medium))
                    if row.kind == .localOnly {
                        OrzMCTag(String(localized: "local"))
                    }
                }
                if let summary = row.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let installed = row.installedVersion {
                    Text("Installed: \(installed)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if manager.busyPlugin == row.name {
                ProgressView().controlSize(.small)
            } else if row.updateAvailable {
                Button("Update") { Task { await manager.install(row) } }
                    .help("Download to plugins/update/ — applied on next restart")
            } else if row.isInstalled {
                Text(row.latestVersion == nil ? "Installed" : "Up to date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if row.kind == .localOnly {
                Text("—").foregroundStyle(.secondary)
            } else {
                Button("Install") { Task { await manager.install(row) } }
                    .help("Download to plugins/ — loaded on next start")
            }
        }
        .padding(.vertical, 2)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
            if let message = manager.lastMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = manager.error {
                OrzMCBanner(verbatim: error.description, role: .error)
            }
            HStack {
                Text("New: plugins/ · Updates: plugins/update/ (applied on next restart)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { manager.refreshLocal() }
            }
        }
        .padding(OrzMCTheme.Spacing.md)
    }
}
