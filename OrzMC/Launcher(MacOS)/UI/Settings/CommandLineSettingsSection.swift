//
//  CommandLineSettingsSection.swift
//  OrzMC
//
//  Created by pi on 2026/10/17.
//

import SwiftUI

/// 设置页的「命令行工具」区块：显示 PATH 上 `orzmc` 的安装事实，并提供
/// **GUI → CLI** 的安装入口（D7 的另一半；另一半是 CLI 的 `orzmc app`）。
struct CommandLineSettingsSection: View {
    @State private var model = CommandLineToolModel()
    @State private var pendingChannel: CommandLineToolModel.Channel?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                statusRow

                Divider().padding(.vertical, 2)

                HStack(spacing: 8) {
                    Button("Install \(CommandLineToolModel.Channel.python.title)") {
                        pendingChannel = .python
                    }
                    Button("Install \(CommandLineToolModel.Channel.swift.title)") {
                        pendingChannel = .swift
                    }
                    .help("两个通道是同一份规范的两个发布源；后装者覆盖先装者")
                    Spacer()
                    Button {
                        model.refresh()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help("Re-read install.conf")
                }
                .disabled(model.isInstalling)

                if model.isInstalling {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Running installer…").font(.footnote).foregroundStyle(.secondary)
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
            confirmationTitle,
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
            Text("""
            This downloads and runs the official OrzMC installer:

            \(channel.oneLiner)

            It installs to ~/.local/bin and may add that directory to your shell PATH.
            No administrator rights are needed.
            """)
        }
    }

    private var confirmationTitle: String {
        "Install orzmc CLI?"
    }

    @ViewBuilder
    private var statusRow: some View {
        if let status = model.status {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("orzmc \(status.version)")
                        .font(.headline)
                    Text(status.surfaceText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
            }
        } else {
            HStack {
                Text("orzmc CLI is not installed on this Mac.")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.footnote)
        }
    }
}

#Preview {
    CommandLineSettingsSection()
        .padding()
        .frame(width: 560)
}
