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
/// 设计约定（macOS HIG + 本项目补充）：
/// - 用**系统 `Form` + `Section` + `.formStyle(.grouped)`**，而不是自己用 `GroupBox` +
///   `Label.font(.title)` 拼“卡片”；这样行高、内边距、深色模式、提高对比度都由系统决定。
/// - 设置项用**分页**（通用 / 服务器 / 命令行 / 关于），避免一个长滚动页。
/// - 每一行用 `LabeledContent`：标题在左、控件在右，标签与控件基线对齐。
/// - **section 标题已经说明“这一块是什么”，行标签就不要再说一遍**：曾经「游戏目录」既是
///   section 标题、又是行标签；「服务器核心」同样重复，看起来像没写完的界面。
/// - **CLI 参数说明放 `.help()`**，正文只留“用户为什么要关心”的一句话。设置页不是手册，
///   `--root-dir` / `--min-mem` / `--type` 这类开关留在悬停提示里就够了。
/// - **低频项渐进披露**：JVM 调试参数只在开关打开后才出现，关着的时候不占一行。
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

    /// 记住上次看的那一页（也让「设置」每次打开都落在用户上次的位置）。
    @AppStorage("settingsTab") private var selectedTab: SettingsTab = .general

    var body: some View {
        TabView(selection: $selectedTab) {
            GeneralSettingsView(settings: app.settings, rootDir: rootDir, java: app.java)
                .tabItem { Label("General", systemImage: "gearshape") }
                .tag(SettingsTab.general)

            ClientSettingsView(settings: app.settings)
                .tabItem { Label("Client", systemImage: "gamecontroller") }
                .tag(SettingsTab.client)

            ServerSettingsView(settings: app.settings)
                .tabItem { Label("Server", systemImage: "xserve") }
                .tag(SettingsTab.server)

            ToolsSettingsView()
                .tabItem { Label("Command Line", systemImage: "terminal") }
                .tag(SettingsTab.tools)

            ShortcutsSettingsView()
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
                .tag(SettingsTab.shortcuts)

            AboutSettingsView()
                .tabItem { Label("About", systemImage: "info.circle") }
                .tag(SettingsTab.about)
        }
        .frame(minWidth: 600, idealWidth: 640, minHeight: 440, idealHeight: 520)
        // 打开设置时不要抢焦点：SwiftUI 会把光标自动放进第一个输入框，绿色焦点环
        // 在第一眼看上去像“这条校验没通过”。让窗口自己成为第一响应者即可。
        .task {
            try? await Task.sleep(for: .milliseconds(250))
            NSApp.keyWindow?.makeFirstResponder(nil)
        }
    }
}

/// 设置页的四个分页（`@AppStorage` 需要 `String` 原始值）。
enum SettingsTab: String, CaseIterable, Hashable {
    case general
    case client
    case server
    case tools
    case shortcuts
    case about
}

// MARK: - General

private struct GeneralSettingsView: View {

    @Bindable var settings: SettingsModel
    @Binding var rootDir: String
    let java: JavaRuntimeModel

    @State private var draftRootDir = ""
    @State private var pathError: String?

    private func commitRootDir() {
        let path = draftRootDir.trimmingCharacters(in: .whitespacesAndNewlines)
        guard path.hasPrefix("/"), !path.contains("\0") else {
            pathError = String(localized: "Path must be absolute (start with /).")
            return
        }
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), !isDirectory.boolValue {
            pathError = String(localized: "Choose a folder, not a file.")
            return
        }
        let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
        if normalized != rootDir { rootDir = normalized }
        draftRootDir = rootDir
        pathError = nil
    }

    var body: some View {
        Form {
            Section {
                Picker("Theme", selection: $settings.appearance) {
                    ForEach(SettingsModel.Appearance.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            } header: {
                Text("Appearance")
            }

            Section {
                LabeledContent("Path") {
                    // 输入框吃掉剩余宽度，按钮保持固有宽度：位置可预测，不再靠 ViewThatFits 猜。
                    HStack(spacing: OrzMCTheme.Spacing.sm) {
                        gameFolderField
                        gameFolderButtons
                    }
                }
                .help("Same as the CLI's --root-dir. One folder per instance — switching it switches every instance.")

                if let pathError {
                    OrzMCBanner(verbatim: pathError, role: .error)
                }
            } header: {
                Text("Game Folder")
            }

            Section {
                LabeledContent("Installed") {
                    HStack(spacing: OrzMCTheme.Spacing.sm) {
                        Text(installedJavaText)
                            .font(.body.monospaced())
                            .foregroundStyle(java.installedMajors.isEmpty
                                ? AnyShapeStyle(.secondary)
                                : AnyShapeStyle(.primary))
                        Spacer()
                        Button {
                            java.refresh()
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .help("Rescan the managed runtimes")
                        .accessibilityLabel("Rescan installed Java runtimes")

                        Button {
                            revealInFinder(javaDir)
                        } label: {
                            Image(systemName: "folder")
                        }
                        .help("Show the managed Java folder in Finder")
                        .accessibilityLabel("Show the managed Java folder in Finder")
                    }
                }
                .help("Runtimes are managed by the engine under <game folder>/java/<major>. A missing version is downloaded on launch, so this never blocks you.")

                // 缺版本时才多说一句：平时这一行是噪音。
                if let required = java.requiredMajor, java.status == .missing {
                    OrzMCBanner("This version needs Java \(required); it will be installed automatically on launch.", role: .info)
                }
            } header: {
                Text("Java")
            }
        }
        .formStyle(.grouped)
        .labeledContentStyle(.orzMCFieldRow)
        .focusSection()
        .onAppear {
            draftRootDir = rootDir
            java.refresh()
        }
        .onChange(of: rootDir) { oldValue, newValue in
            if draftRootDir == oldValue { draftRootDir = newValue }
            java.refresh()
        }
        // 用户重新编辑就清掉上一次的路径错误，别让旧红条挂在新输入旁边。
        .onChange(of: draftRootDir) { pathError = nil }
    }

    private var installedJavaText: String {
        java.installedMajors.isEmpty
            ? String(localized: "None")
            : java.installedMajors.map(String.init).formatted(.list(type: .and))
    }

    private var javaDir: URL {
        URL(fileURLWithPath: GamePlan.layout(root: rootDir, version: "").javaDir)
    }

    private func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private var gameFolderField: some View {
        TextField("", text: $draftRootDir, prompt: Text("Absolute path"))
            .onSubmit(commitRootDir)
            .onExitCommand { draftRootDir = rootDir; pathError = nil }
            .textFieldStyle(.roundedBorder)
            // `Form` 里 TextField 即使标签为空也会占一列 → 显式隐藏，输入框才会紧贴标签列。
            .labelsHidden()
            // 表单默认把「值」右对齐；路径需要从左读。
            .multilineTextAlignment(.leading)
            // 等宽但**与相邻按钮同字号**：`.caption` 等宽比按钮文字小一号，看起来“文字没对齐”。
            .font(.body.monospaced())
    }

    @ViewBuilder
    private var gameFolderButtons: some View {
        Button("Apply", action: commitRootDir)
            .disabled(draftRootDir == rootDir)

        Button("Choose…") { chooseRootDir() }

        Button {
            draftRootDir = GamePlan.defaultRoot
            commitRootDir()
        } label: {
            Image(systemName: "arrow.uturn.backward")
        }
        .help("Reset to \(GamePlan.defaultRoot)")
        .accessibilityLabel("Reset game folder to default")
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
        draftRootDir = url.path
        commitRootDir()
    }
}

// MARK: - Client

private struct ClientSettingsView: View {

    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
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
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .autocorrectionDisabled()
                }
                .help("Prefilled on every client launch; required before starting a client.")

                LabeledContent("JVM memory") {
                    // 基线对齐：分隔符是文字，输入框是控件，默认 `.center` 会让「–」比字段内文字偏高/偏低。
                    HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.xs) {
                        TextField("", text: $settings.minMem, prompt: Text("512M"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)   // 数值惯用右对齐
                            .frame(width: 84)
                        Text("–")
                            .foregroundStyle(.tertiary)
                        TextField("", text: $settings.maxMem, prompt: Text("2G"))
                            .textFieldStyle(.roundedBorder)
                            .labelsHidden()
                            .multilineTextAlignment(.trailing)
                            .frame(width: 84)
                    }
                }
                .help("Same rules as the CLI's --min-mem / --max-mem.")

                if let message = settings.memoryValidationMessage {
                    OrzMCBanner("Invalid memory setting: \(message) (expected e.g. 512M / 2G)", role: .error)
                }
            } header: {
                Text("Client")
            }
        }
        .formStyle(.grouped)
        .labeledContentStyle(.orzMCFieldRow)
        .focusSection()
    }
}

// MARK: - Server

private struct ServerSettingsView: View {

    @Bindable var settings: SettingsModel

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $settings.serverSoftware) {
                    ForEach(SettingsModel.ServerSoftware.allCases) { software in
                        Text(software.rawValue).tag(software)
                    }
                }
                .pickerStyle(.segmented)
                .help("Same four values as the CLI's --type.")

                OrzMCBanner("Only used when the game mode is Server.", role: .info)
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

                // 渐进披露：关掉调试时，参数这一行连出现都不出现——它此刻没有任何意义，
                // 留着只是一个灰掉的等宽长条。
                if settings.enableJVMDebugger {
                    LabeledContent("Arguments") {
                        TextField(
                            "",
                            text: $settings.jvmDebuggerArgs,
                            prompt: Text(Constants.defaultJVMDebuggerArgs)
                        )
                        .textFieldStyle(.roundedBorder)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .font(.body.monospaced())
                    }
                }

                OrzMCBanner("Adds -agentlib:jdwp=… to the server JVM so a debugger can attach. Keep it off unless you need it.", role: .info)
            } header: {
                Text("Debugging")
            }
        }
        .formStyle(.grouped)
        .labeledContentStyle(.orzMCFieldRow)
        .focusSection()
    }
}

// MARK: - Command line

private struct ToolsSettingsView: View {
    var body: some View {
        Form {
            CommandLineSettingsSection()
        }
        .formStyle(.grouped)
        .labeledContentStyle(.orzMCFieldRow)
        .focusSection()
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
                // 三行声明保持可见（Usage Guidelines 要求"展示"而不是"折叠"），
                // 但降成 footnote —— 它不该比版本信息更抢眼；页脚里重复的商标句已删。
                Text(Compliance.disclaimer)
                Text(Compliance.disclaimerZh)
                Text(Compliance.trademarkZh)
            } header: {
                Text("Disclaimer")
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .textCase(nil)
        }
        .formStyle(.grouped)
        .labeledContentStyle(.orzMCFieldRow)
        .focusSection()
    }
}

#Preview {
    SettingsView()
        .environment(AppModel())
}
