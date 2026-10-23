//
//  SelfHostedServerSettingsView.swift
//  OrzMC
//

import OrzMCDesignSystem
import SwiftUI

/// 自建服务器的连接设置：地址 / 端口 / RCON。
///
/// 校验只做"能不能连"这一层（端口范围、地址非空）；**不在这里发网络请求**——
/// 保存后回到页面由状态卡自己去查，失败信息显示在那里。
struct SelfHostedServerSettingsView: View {
    let profile: SelfHostedServerProfile
    let onSave: (SelfHostedServerProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft: SelfHostedServerProfile
    @State private var portText: String
    @State private var rconPortText: String
    @State private var rconPassword: String
    @State private var errorMessage: String?

    init(profile: SelfHostedServerProfile, onSave: @escaping (SelfHostedServerProfile) -> Void) {
        self.profile = profile
        self.onSave = onSave
        _draft = State(initialValue: profile)
        _portText = State(initialValue: String(profile.port))
        _rconPortText = State(initialValue: String(profile.rconPort))
        _rconPassword = State(initialValue: SelfHostedServerProfile.rconPassword() ?? "")
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
            }
            .formStyle(.grouped)
            .navigationTitle(String(localized: "Server Settings"))
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
        }
#if os(macOS)
        .frame(minWidth: 460, minHeight: 420)
#endif
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
            SelfHostedServerProfile.saveRCONPassword(rconPassword)
        }

        onSave(updated)
        dismiss()
    }
}

#Preview {
    SelfHostedServerSettingsView(profile: SelfHostedServerProfile()) { _ in }
}
