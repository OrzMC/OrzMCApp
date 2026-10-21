//
//  SettingsView.swift
//  OrzMC
//
//  Created by wangzhizhou on 2024/9/26.
//

import AppKit
import Game
import OrzMCDesignSystem
import SwiftUI

/// 设置窗口。
///
/// 设计约定（macOS HIG）：
/// - 用**系统 `Form` + `Section` + `.formStyle(.grouped)`**，而不是自己用 `GroupBox` +
///   `Label.font(.title)` 拼“卡片”；这样行高、内边距、深色模式、提高对比度都由系统决定。
/// - 设置项用**分页**（General / Server / Tools / About），避免一个 620pt 的长滚动页。
/// - 每一行用 `LabeledContent`：标题在左、控件在右，标签与控件基线对齐。
/// - 路径/参数用等宽字体；错误用统一 `OrzMCBanner`，不再各处 `foregroundStyle(.red)`。
struct SettingsView: View {

    @Environment(AppModel.self) private var app

    /// 根目录的唯一写入口：必须经过 `AppModel.rootDir`，这样会同时刷新
    /// 版本目录、JRE 扫描和进程视图（直接写 `SettingsModel.rootDir` 会漏掉这些）。
    private var rootDir: Binding<String> {
        Binding(
            get: { app.rootDir },
            set: { app.rootDir = $0 }
        )
    }

    var body: some View {
        TabView {
            GeneralSettingsView(settings: app.settings, rootDir: rootDir)
                .tabItem { Label("General", systemImage: "gearshape") }

            ServerSettingsView(settings: app.settings)
                .tabItem { Label("Server", systemImage: "xserve") }

            ToolsSettingsView()
                .tabItem { Label("Tools", systemImage: "wrench.and.screwdriver") }

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 560, height: 480)
    }
}

// MARK: - General

private struct GeneralSettingsView: View {

    @Bindable var settings: SettingsModel
    @Binding var rootDir: String

    private var isRootDirValid: Bool { rootDir.hasPrefix("/") }

    var body: some View {
        Form {
            Section {
                LabeledContent("Game folder") {
                    HStack(spacing: OrzMCTheme.Spacing.sm) {
                        TextField("", text: $rootDir, prompt: Text("Absolute path"))
                            .textFieldStyle(.roundedBorder)
                            .font(OrzMCTheme.Typography.code)
                            .labelsHidden()

                        Button("Choose…") { chooseRootDir() }

                        Button {
                            rootDir = GamePlan.defaultRoot
                        } label: {
                            Image(systemName: "arrow.uturn.backward")
                        }
                        .help("Reset to \(GamePlan.defaultRoot)")
                        .accessibilityLabel("Reset game folder to default")
                    }
                }

                if !isRootDirValid {
                    OrzMCBanner("Path must be absolute (start with /).", role: .error)
                } else {
                    OrzMCBanner(
                        "Multiple instances = one game folder each (same as the CLI's --root-dir).",
                        role: .info
                    )
                }
            } header: {
                Text("Game Folder")
            }

            Section {
                Picker("Client type", selection: $settings.clientType) {
                    ForEach(SettingsModel.ClientKind.allCases) { kind in
                        Text(kind.rawValue).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                LabeledContent("Username") {
                    TextField("", text: $settings.username, prompt: Text("Offline player name"))
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .labelsHidden()
                }

                LabeledContent("JVM memory") {
                    HStack(spacing: OrzMCTheme.Spacing.xs) {
                        TextField("", text: $settings.minMem, prompt: Text("512M"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 84)
                        Text("–")
                            .foregroundStyle(.secondary)
                        TextField("", text: $settings.maxMem, prompt: Text("2G"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .frame(width: 84)
                    }
                }

                if let message = settings.memoryValidationMessage {
                    OrzMCBanner("Invalid memory setting: \(message) (expected e.g. 512M / 2G)", role: .error)
                } else {
                    OrzMCBanner("Same rules as the CLI (--min-mem / --max-mem).", role: .info)
                }
            } header: {
                Text("Client")
            }
        }
        .formStyle(.grouped)
    }

    /// 选游戏根目录（多实例）：只挑目录，不创建——引擎会在下载时就地建好。
    private func chooseRootDir() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootDir = url.path
    }
}

// MARK: - Server

private struct ServerSettingsView: View {

    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Server core", selection: $settings.serverSoftware) {
                    ForEach(SettingsModel.ServerSoftware.allCases) { software in
                        Text(software.rawValue).tag(software)
                    }
                }
                .pickerStyle(.segmented)

                OrzMCBanner(
                    "Used when the game mode is Server. The CLI's --type accepts the same four values.",
                    role: .info
                )
            } header: {
                Text("Server Core")
            }

            Section {
                Toggle("Remote JVM debugging", isOn: $settings.enableJVMDebugger)
                    .onChange(of: settings.enableJVMDebugger) {
                        if settings.enableJVMDebugger, settings.jvmDebuggerArgs.isEmpty {
                            settings.jvmDebuggerArgs = Constants.defaultJVMDebuggerArgs
                        }
                    }

                LabeledContent("Arguments") {
                    TextField(
                        "",
                        text: $settings.jvmDebuggerArgs,
                        prompt: Text(Constants.defaultJVMDebuggerArgs)
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(OrzMCTheme.Typography.code)
                    .labelsHidden()
                    .disabled(!settings.enableJVMDebugger)
                }

                OrzMCBanner(
                    "Adds -agentlib:jdwp=… so a debugger can attach to the server JVM. Keep it off unless you need it.",
                    role: .info
                )
            } header: {
                Text("Debugging")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Tools

private struct ToolsSettingsView: View {
    var body: some View {
        Form {
            CommandLineSettingsSection()
        }
        .formStyle(.grouped)
    }
}

// MARK: - About

private struct AboutSettingsView: View {

    private var versionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return "\(version) (\(build))"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("OrzMC", value: versionText)
                LabeledContent("Engine", value: "OrzMCKit")
            } header: {
                Text("About")
            }

            Section {
                HStack(spacing: OrzMCTheme.Spacing.lg) {
                    if let url = URL(string: Compliance.website) {
                        Link("Website", destination: url)
                    }
                    if let url = URL(string: Compliance.contactURL) {
                        Link("Contact Author", destination: url)
                    }
                    if let url = URL(string: Compliance.privacyURL) {
                        Link("Privacy Policy", destination: url)
                    }
                    Spacer()
                }

                HStack(spacing: OrzMCTheme.Spacing.md) {
                    Image("alipay")
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 96, height: 112)
                        .accessibilityLabel("Alipay QR code")

                    VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
                        Text("Buy Me a Coffee")
                            .font(.headline)
                        Text("OrzMC is free and open source. If it helps you, you can support the author.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
            } header: {
                Text("Support")
            }

            Section {
                Text(Compliance.disclaimer)
                Text(Compliance.disclaimerZh)
                Text(Compliance.trademarkZh)
            } header: {
                Text("Disclaimer")
            } footer: {
                Text("Minecraft is a trademark of Mojang Synergies AB. OrzMC is not affiliated with Mojang or Microsoft.")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
