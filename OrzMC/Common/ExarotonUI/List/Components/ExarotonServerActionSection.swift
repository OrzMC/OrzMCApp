//
//  ExarotonServerActionSection.swift
//  OrzMC
//
//  Created by Codex on 2026/5/22.
//

import OrzMCDesignSystem
import OrzMCRemoteHosting
import SwiftUI

struct ExarotonServerActionSection: View {
    @Environment(ExarotonServerModel.self) private var model

    let server: ExarotonServer
    let status: ServerStatus

    @Binding var serverRAM: Int32
    @Binding var isLoading: Bool

    private let actionPolicy = RemoteServerListPolicy()

    @State private var confirmStop = false
    @State private var confirmRestart = false

    var body: some View {
        Section("Actions") {
            if serverRAM > 0 {
                LabeledContent("Memory") {
                    HStack(spacing: OrzMCTheme.Spacing.sm) {
                        Text("\(serverRAM) GB")
                            .font(OrzMCTheme.Typography.numeric)
                            .foregroundStyle(.secondary)
                        Stepper("", value: $serverRAM, in: 2...16, step: 1)
                            .labelsHidden()
                    }
                }
                .disabled(isLoading || status != .OFFLINE)
            }

            HStack(spacing: OrzMCTheme.Spacing.sm) {
                Button("Start Server", systemImage: "play.fill") {
                    perform(.start)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canPerform(.start))

                ControlGroup {
                    Button("Stop", systemImage: "stop.fill") {
                        confirmStop = true
                    }
                    .disabled(!canPerform(.stop))

                    Button("Restart", systemImage: "arrow.clockwise") {
                        confirmRestart = true
                    }
                    .disabled(!canPerform(.restart))
                }
                Spacer(minLength: 0)
            }
            .disabled(isLoading)

            OrzMCBanner(
                "Actions run on exaroton's side. Players connected to the server are disconnected by Stop/Restart.",
                role: .info
            )
        }
        // 破坏性/会断线的远程操作先确认：与本地服务端的 Stop/Restart 保持同一套交互。
        .confirmationDialog("Stop Server?", isPresented: $confirmStop) {
            Button("Stop", role: .destructive) { perform(.stop) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server saves and shuts down. Connected players are disconnected.")
        }
        .confirmationDialog("Restart Server?", isPresented: $confirmRestart) {
            Button("Restart") { perform(.restart) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server stops and starts again. Connected players are disconnected during the restart.")
        }
    }

    private func canPerform(_ action: RemoteServerAction) -> Bool {
        actionPolicy.canPerform(action, on: status.remoteHostingState)
    }

    private func perform(_ action: RemoteServerAction) {
        Task {
            guard let serverID = server.id else {
                model.errorMessage = String(localized: "Server ID is missing.")
                return
            }

            switch action {
            case .start:
                _ = await model.startServer(serverId: serverID)
            case .stop:
                _ = await model.stopServer(serverId: serverID)
            case .restart:
                _ = await model.restartServer(serverId: serverID)
            }
        }
    }
}
