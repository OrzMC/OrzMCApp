//
//  SettingsView.swift
//  OrzMC
//
//  Created by wangzhizhou on 2024/9/26.
//

import AppKit
import Game
import SwiftUI
import SwiftUIX

struct SettingsView: View {

    @Environment(SettingsModel.self) private var model

    var body: some View {
        @Bindable var model = model

        ScrollView {
            VStack(spacing: 20) {
                GroupBox {
                    VStack(alignment: .leading) {
                        HStack {
                            Text("Server Core")
                                .font(.headline)
                            Spacer()
                            Picker("", selection: $model.serverSoftware) {
                                ForEach(SettingsModel.ServerSoftware.allCases) { software in
                                    Text(software.rawValue).tag(software)
                                }
                            }
                            .pickerStyle(.segmented)
                        }

                        Divider().padding(.vertical, 4)

                        HStack {
                            Toggle(isOn: $model.enableJVMDebugger) {
                                Text("Remote JVM Debugging")
                            }
                            .onChange(of: model.enableJVMDebugger) {
                                if model.enableJVMDebugger, model.jvmDebuggerArgs.isEmpty {
                                    model.jvmDebuggerArgs = Constants.defaultJVMDebuggerArgs
                                }
                            }
                            Spacer()
                        }

                        TextField(text: $model.jvmDebuggerArgs, prompt: Text(Constants.defaultJVMDebuggerArgs)) {
                        }
                        .textFieldStyle(.roundedBorder)
                        .disabled(!model.enableJVMDebugger)
                    }
                } label: {
                    Label("Server", systemImage: "xserve")
                        .font(.title)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Client Type")
                            Spacer()
                            Picker("", selection: $model.clientType) {
                                ForEach(SettingsModel.ClientKind.allCases) { kind in
                                    Text(kind.rawValue).tag(kind)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .frame(width: 200)
                        }

                        Divider().padding(.vertical, 4)

                        HStack {
                            Text("JVM Memory")
                            Spacer()
                            TextField("512M", text: $model.minMem)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            Text("–")
                            TextField("2G", text: $model.maxMem)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                        }

                        if let message = model.memoryValidationMessage {
                            Text("Invalid: \(message) (expected e.g. 512M / 2G)")
                                .font(.caption)
                                .foregroundStyle(Color.red)
                        } else {
                            Text("Same rules as the CLI (--min-mem / --max-mem).")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } label: {
                    Label("Game", systemImage: "gamecontroller")
                        .font(.title)
                }

                CommandLineSettingsSection()

                GroupBox {
                    HStack(spacing: 12) {
                        Button("Contact Author", systemImage: "envelope") {
                            if let url = URL(string: Compliance.contactURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }

                        BuyMeCoffeeButton(
                            content:
                                Image("alipay")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 100, height: 118)
                        )

                        Spacer()
                    }
                } label: {
                    Label("Support", systemImage: "heart")
                        .font(.title)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(Compliance.disclaimer)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("\(Compliance.disclaimerZh)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("\(Compliance.trademarkZh)")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button("联系作者") {
                                if let url = URL(string: Compliance.contactURL) { NSWorkspace.shared.open(url) }
                            }
                            Button("隐私政策") {
                                if let url = URL(string: Compliance.privacyURL) { NSWorkspace.shared.open(url) }
                            }
                        }
                        .font(.footnote)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } label: {
                    Label("Disclaimer", systemImage: "info.circle")
                        .font(.title)
                }
            }
            .padding()
        }
        .frame(width: 600, height: 620)
    }
}

#Preview {
    SettingsView()
        .environment(SettingsModel())
}
