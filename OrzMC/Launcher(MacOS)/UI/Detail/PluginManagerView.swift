//
//  PluginManagerView.swift
//  OrzMC
//
//  插件管理面板：已装插件 + Hangar 目录 → 安装 / 更新。
//

import SwiftUI
import Game
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
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 620, height: 480)
        .task {
            manager.bind(versionId: versionId, rootDir: app.settings.rootDir)
            await manager.loadCatalogIfNeeded()
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Plugins — \(versionId)")
                .font(.headline)
            if manager.updateCount > 0 {
                Text("\(manager.updateCount) update(s)")
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.orange.opacity(0.15))
                    .foregroundStyle(Color.orange)
                    .clipShape(Capsule())
            }
            Spacer()
            if manager.isLoadingCatalog || manager.isCheckingUpdates {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await manager.loadCatalogIfNeeded(); await manager.checkUpdates() }
            } label: {
                Label("Check Updates", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(manager.isLoadingCatalog || manager.isCheckingUpdates)
            Button {
                Task { await manager.updateAll() }
            } label: {
                Label("Update All", systemImage: "arrow.down.circle")
            }
            .disabled(manager.updateCount == 0 || manager.busyPlugin != nil)
        }
        .padding(12)
    }

    private var content: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search plugins", text: $manager.searchText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Show catalog", isOn: $showHangarCatalog)
                    .toggleStyle(.checkbox)
                    .help("Hangar 目录里的插件（关闭后只看本地已装）")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            List {
                if !manager.installedJars.isEmpty {
                    Section("Installed (\(manager.installedJars.count))") {
                        ForEach(visibleRows.filter(\.isInstalled)) { row in
                            rowView(row)
                        }
                    }
                }
                Section("Available") {
                    ForEach(visibleRows.filter { !$0.isInstalled }) { row in
                        rowView(row)
                    }
                }
            }
            .listStyle(.inset)
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
                        Text("local")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .background(Color.secondary.opacity(0.15))
                            .clipShape(Capsule())
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
        VStack(alignment: .leading, spacing: 4) {
            if let message = manager.lastMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = manager.error {
                Text(error.description)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Text("New: plugins/ · Updates: plugins/update/ (applied on next restart)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Refresh") { manager.refreshLocal() }
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }
}
