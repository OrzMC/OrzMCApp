//
//  CommandLineSettingsSection.swift
//  OrzMC
//
//  Created by pi on 2026/10/17.
//

import OrzMCLauncher
import SwiftUI

/// 设置页的「命令行工具」区块：显示 PATH 上 `orzmc` 的安装事实，并提供
/// **GUI → CLI** 的安装入口（D7 的另一半；另一半是 CLI 的 `orzmc app`）。
///
/// `install.conf` 的 `surface` 在这里是**一等公民**（规范 `install-update.md` §3.1）：
/// 显示「谁装的」+「从哪个通道来的」，并据此决定默认动作——
/// 有真身时优先 **Update**（保留 `surface`），没有才 Fallback 到 Install（会把 `surface` 写成本应用）。
struct CommandLineSettingsSection: View {
    @State private var model = CommandLineToolModel()
    @State private var pendingChannel: CommandLineToolModel.Channel?
    @State private var pendingUninstall = false

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                statusRow

                Divider().padding(.vertical, 2)

                actionRow

                if model.isBusy {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Running…").font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = model.errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(Color.red)
                }

                if !model.log.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(model.log.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                            .padding(6)
                        }
                        .frame(height: 120)
                        .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                        .onChange(of: model.log.count) {
                            proxy.scrollTo(model.log.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Label("Command Line", systemImage: "terminal")
                .font(.title)
        }
        .task { model.refresh() }
        .confirmationDialog(
            "Install orzmc CLI?",
            isPresented: Binding(
                get: { pendingChannel != nil },
                set: { if !$0 { pendingChannel = nil } }
            ),
            presenting: pendingChannel
        ) { channel in
            Button("Install \(channel.title)") {
                Task {
                    await model.install(channel)
                    pendingChannel = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingChannel = nil }
        } message: { channel in
            Text(
                """
                This downloads and runs the official OrzMC installer:

                \(channel.oneLiner)

                It installs to ~/.local/bin and may add that directory to your shell PATH. \
                No administrator rights are needed.

                \(InstallSurfacePolicy.reinstallNotice())
                """
            )
        }
        .confirmationDialog(
            "Uninstall orzmc CLI?",
            isPresented: $pendingUninstall
        ) {
            Button("Uninstall", role: .destructive) {
                Task { await model.uninstall() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                """
                Runs `orzmc uninstall --yes`: removes the binary, the PATH line it added, \
                the shell completion, and the install record. Your game files are kept.
                """
            )
        }
    }

    // MARK: 状态

    @ViewBuilder
    private var statusRow: some View {
        if let status = model.status {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text("orzmc \(status.version)")
                        .font(.headline)
                    Text(status.surfaceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let channel = status.channel {
                        Text(channel.title)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    if status.binaryExists {
                        Button("Reveal") { model.revealBinary() }
                            .font(.caption)
                    }
                }

                Text(status.binaryPath)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(status.binaryExists ? Color.secondary : Color.red)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if status.isBroken {
                    Text("The recorded binary is missing — reinstall to repair the record.")
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                } else if let completion = status.completionFile, !completion.isEmpty {
                    Text("completion: \(completion)")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Text("record: \(status.recordPath)")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        } else {
            HStack {
                Text("orzmc CLI is not installed for this user.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: 动作

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: 8) {
            if let status = model.status, status.canUpdateInPlace {
                // 有真身：默认动作是**升级**（保留 surface/source），不是重装。
                Button("Update") {
                    Task { await model.update() }
                }
                .buttonStyle(.borderedProminent)
                .help("Runs `orzmc update --yes` — keeps the recorded origin (surface/source)")

                Menu("Reinstall…") {
                    ForEach(CommandLineToolModel.Channel.allCases) { channel in
                        Button(channel.title) { pendingChannel = channel }
                    }
                }
                .fixedSize()
                .help("Re-runs the official installer; the record will say installed by this app")

                Button("Uninstall", role: .destructive) { pendingUninstall = true }
            } else {
                ForEach(CommandLineToolModel.Channel.allCases) { channel in
                    Button("Install \(channel.title)") { pendingChannel = channel }
                }
                if model.status != nil {
                    Text("(record exists but the binary is missing)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                model.refresh()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath")
            }
            .help("Re-read install.conf")
        }
        .disabled(model.isBusy)
    }
}
