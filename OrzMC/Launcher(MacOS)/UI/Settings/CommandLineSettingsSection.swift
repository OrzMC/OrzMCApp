//
//  CommandLineSettingsSection.swift
//  OrzMC
//
//  Created by pi on 2026/10/17.
//

import OrzMCDesignSystem
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
        Section {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
                statusRow

                Divider()

                actionRow

                if model.isBusy {
                    HStack(spacing: OrzMCTheme.Spacing.sm) {
                        ProgressView().controlSize(.small)
                        Text("Running…").font(.footnote).foregroundStyle(.secondary)
                    }
                }

                if let errorMessage = model.errorMessage {
                    OrzMCBanner(verbatim: errorMessage, role: .error)
                }

                if !model.log.isEmpty {
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(Array(model.log.enumerated()), id: \.offset) { index, line in
                                    Text(line)
                                        .font(OrzMCTheme.Typography.console)
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .id(index)
                                }
                            }
                            .padding(OrzMCTheme.Spacing.xs)
                        }
                        .frame(height: 120)
                        .consoleSurface(cornerRadius: OrzMCTheme.Radius.sm)
                        .onChange(of: model.log.count) {
                            proxy.scrollTo(model.log.count - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Label("Command Line", systemImage: "terminal")
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
                HStack(spacing: OrzMCTheme.Spacing.sm) {
                    Text("orzmc \(status.version)")
                        .font(.headline)
                    Text(surfaceText(for: status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let channel = status.channel {
                        // 通道名是专有名词（Python CLI / Swift CLI），按原文显示。
                        OrzMCTag(channel.title)
                    }
                    Spacer()
                    if status.binaryExists {
                        Button("Reveal") { model.revealBinary() }
                            .font(.caption)
                    }
                }

                Text(status.binaryPath)
                    .font(OrzMCTheme.Typography.code)
                    .foregroundStyle(status.binaryExists ? AnyShapeStyle(.secondary) : AnyShapeStyle(OrzMCTheme.Palette.danger))
                    .lineLimit(1)
                    .truncationMode(.middle)

                if status.isBroken {
                    OrzMCBanner("The recorded binary is missing — reinstall to repair the record.", role: .warning)
                }

                // 补全脚本与记录文件平时没人看，折起来；出问题时仍可展开核对。
                DisclosureGroup("Install record") {
                    VStack(alignment: .leading, spacing: 3) {
                        if let completion = status.completionFile, !completion.isEmpty {
                            Text("completion: \(completion)")
                                .font(OrzMCTheme.Typography.code)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Text("record: \(status.recordPath)")
                            .font(OrzMCTheme.Typography.code)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Text("orzmc CLI is not installed for this user.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    /// `InstallSurface.displayText` 在共享库里是硬编码英文，这里按来源给界面本地化文案
    /// （约定：依赖库的英文标题由应用侧本地化，不去改共享库的展示字符串）。
    private func surfaceText(for status: CommandLineToolModel.Status) -> String {
        switch status.installSurface {
        case .cli: return String(localized: "Installed from a terminal")
        case .gui: return String(localized: "Installed from this app")
        case nil: return String(localized: "Origin unknown (legacy record)")
        }
    }

    // MARK: 动作

    @ViewBuilder
    private var actionRow: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
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
            .accessibilityLabel("Refresh command line install record")
        }
        .disabled(model.isBusy)
    }
}
