//
//  SettingsView.swift
//  OrzMC
//
//  Created by wangzhizhou on 2024/9/26.
//

import AppKit
import SwiftUI
import SwiftUIX

struct SettingsView: View {
    
    @Environment(SettingsModel.self) private var model
        
    var body: some View {
        @Bindable var model = model
        
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
                HStack(spacing: 12) {
                    Button("Contact Author", systemImage: "envelope") {
                        if let url = URL(string: "mailto:\(Constants.feedbackEmail)") {
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
                    Text(Constants.disclaimer)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("OrzMC 是独立的社区开源项目，与 Mojang / Microsoft 无隶属关系，对本应用负责。联系：\(Constants.feedbackEmail)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } label: {
                Label("Disclaimer", systemImage: "info.circle")
                    .font(.title)
            }

            Spacer()
        }
        .padding()
        .frame(width: 600, height: 400)
    }
}

#Preview {
    SettingsView()
        .environment(SettingsModel())
}
