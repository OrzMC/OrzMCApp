//
//  SelfHostedServerSettingsView.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCLauncher
import OrzMCProtocol
import SwiftUI

/// 自建服务器的连接设置：地址 / 端口 / RCON，以及删除这台服务器。
///
/// 校验只做"能不能连"这一层（端口范围、地址非空）；**不在这里发网络请求**——
/// 保存后回到页面由状态卡自己去查，失败信息显示在那里。
struct SelfHostedServerSettingsView: View {
    let profile: SelfHostedServerProfile
    /// `(保存后的档案, RCON 密码, 是否删除)` —— 密码交回给模型写 Keychain。
    let onDone: (SelfHostedServerProfile, String?, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SelfHostedServerProfile
    @State private var portText: String
    @State private var rconPortText: String
    @State private var rconPassword: String
    @State private var errorMessage: String?
    @State private var confirmDelete = false
    /// 「测试连接」的结果（保存前就能验证地址 / 密码，不用先存一份坏配置）。
    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle
        case running
        case ok(String)
        case failed(String)
    }

    private var isNew: Bool {
        // 新建时地址一定为空（`addServer()` 造的是空档案）。
        profile.host.isEmpty
    }

    init(profile: SelfHostedServerProfile, onDone: @escaping (SelfHostedServerProfile, String?, Bool) -> Void) {
        self.profile = profile
        self.onDone = onDone
        _draft = State(initialValue: profile)
        _portText = State(initialValue: String(profile.port))
        _rconPortText = State(initialValue: String(profile.rconPort))
        _rconPassword = State(initialValue: SelfHostedCredentials.password(for: profile.id) ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Server") {
                    LabeledContent("Name") {
                        TextField("", text: $draft.name, prompt: Text("Optional, e.g. Home"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                    }
                    LabeledContent("Address") {
                        TextField("", text: $draft.host, prompt: Text("mc.example.com or 192.168.0.10"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            .autocorrectionDisabled()
                            #if os(iOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                    }
                    LabeledContent("Port") {
                        TextField("", text: $portText, prompt: Text("25565"))
                            .labelsHidden()
                            .textFieldStyle(.roundedBorder)
                            .multilineTextAlignment(.leading)
                            #if os(iOS)
                            .keyboardType(.numberPad)
                            #endif
                    }
                }

                Section {
                    HStack(spacing: OrzMCTheme.Spacing.sm) {
                        Button {
                            Task { await testConnection() }
                        } label: {
                            if testState == .running {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Test Connection", systemImage: "bolt.horizontal")
                            }
                        }
                        .disabled(testState == .running)

                        Spacer()

                        switch testState {
                        case .idle:
                            EmptyView()
                        case .running:
                            Text("Checking…").font(.caption).foregroundStyle(.secondary)
                        case let .ok(message):
                            Label(message, systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(OrzMCTheme.Palette.success)
                        case let .failed(message):
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .font(.caption)
                                .foregroundStyle(OrzMCTheme.Palette.danger)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                } header: {
                    Text("Verification")
                } footer: {
                    Text("Checks the status port with Server List Ping, and (if RCON is on) runs `list` to verify the password. Nothing is saved.")
                }

                Section {
                    Toggle("Use RCON for console commands", isOn: $draft.rconEnabled)
                    if draft.rconEnabled {
                        LabeledContent("RCON port") {
                            TextField("", text: $rconPortText, prompt: Text("25575"))
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.leading)
                                #if os(iOS)
                                .keyboardType(.numberPad)
                                #endif
                        }
                        LabeledContent("RCON password") {
                            SecureField("", text: $rconPassword)
                                .labelsHidden()
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                } header: {
                    Text("Console")
                } footer: {
                    Text("Ports and the password come from `server.properties` (`rcon.port`, `rcon.password`, `enable-rcon=true`). The password is stored in the system keychain.")
                }

                if let errorMessage {
                    Section {
                        OrzMCBanner(verbatim: errorMessage, role: .error)
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete This Server", role: .destructive) { confirmDelete = true }
                    } footer: {
                        Text("Removes the address, the saved RCON password and the console history on this device. The server itself is not touched.")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isNew ? String(localized: "Add Server") : String(localized: "Server Settings"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .confirmationDialog(
                "Delete This Server?",
                isPresented: $confirmDelete,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    onDone(draft, nil, true)
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the address, the saved RCON password and the console history on this device.")
            }
        }
#if os(macOS)
        .frame(minWidth: 460, minHeight: 460)
#endif
    }

    /// 用**当前草稿**去探一次，不改任何存储。
    private func testConnection() async {
        testState = .running
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        let portText = portText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty, let port = Int(portText), (1...65535).contains(port) else {
            testState = .failed(String(localized: "Enter a valid address and port first."))
            return
        }
        let address = port == 25565 ? host : "\(host):\(port)"

        let probe = MCServerProbe()
        do {
            let summary = try await probe.status(host: host, port: Int32(port))
            var message = summary.versionName ?? String(localized: "Online")
            if let online = summary.playersOnline, let max = summary.playersMax {
                message += " · \(online)/\(max)"
            }
            if summary.latencyMilliseconds > 0 {
                message += " · \(summary.latencyMilliseconds) ms"
            }

            // RCON 打开且填了密码时，顺手用一条 `list` 验证密码（不费事、也不改状态）。
            if draft.rconEnabled, !rconPassword.isEmpty,
               let rconPort = Int(rconPortText.trimmingCharacters(in: .whitespacesAndNewlines)),
               (1...65535).contains(rconPort) {
                do {
                    let reply = try await probe.runRCON(
                        host: host,
                        port: Int32(rconPort),
                        password: rconPassword,
                        command: "list"
                    )
                    let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                    testState = .ok(trimmed.isEmpty ? message : "\(message) · RCON OK")
                } catch {
                    testState = .failed(
                        SelfHostedErrorText.describe(
                            error,
                            address: "\(host):\(rconPort)"
                        )
                    )
                }
                return
            }
            testState = .ok(message)
        } catch {
            testState = .failed(SelfHostedErrorText.describe(error, address: address))
        }
    }

    private func save() {
        errorMessage = nil
        let host = draft.host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            errorMessage = String(localized: "Enter the server address.")
            return
        }
        guard let port = Int(portText.trimmingCharacters(in: .whitespacesAndNewlines)), (1...65535).contains(port) else {
            errorMessage = String(localized: "Port must be a number between 1 and 65535.")
            return
        }
        var updated = draft
        updated.host = host
        updated.port = port

        var password: String?
        if updated.rconEnabled {
            guard let rconPort = Int(rconPortText.trimmingCharacters(in: .whitespacesAndNewlines)),
                  (1...65535).contains(rconPort) else {
                errorMessage = String(localized: "RCON port must be a number between 1 and 65535.")
                return
            }
            guard !rconPassword.isEmpty else {
                errorMessage = String(localized: "Enter the RCON password, or turn RCON off.")
                return
            }
            updated.rconPort = rconPort
            password = rconPassword
        }

        onDone(updated, password, false)
        dismiss()
    }
}

#Preview {
    SelfHostedServerSettingsView(profile: SelfHostedServerProfile()) { _, _, _ in }
}
