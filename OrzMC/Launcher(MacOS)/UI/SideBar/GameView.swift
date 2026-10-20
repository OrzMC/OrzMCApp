//
//  GameView.swift
//  OrzMC
//
//  Created by joker on 4/26/24.
//

import SwiftUI
import MojangAPI
import Game
import OrzMCLauncher

/// 侧边栏：版本列表 + 运行参数表单 + 启动按钮。
///
/// **只做布局与绑定**：过滤/加载/启动/进度全在 `AppModel` 的各个模型里
/// （以前这里有 `reloadList`/`refreshList`/`filteredVersions` 三份自管状态）。
struct GameView: View {

    @Environment(AppModel.self) private var app

    @State private var showOnlyRelease = true
    @FocusState private var usernameTextFieldFocused: Bool

    var body: some View {
        @Bindable var catalog = app.catalog
        @Bindable var settings = app.settings

        VStack(alignment: .leading) {
            GameList(
                versions: catalog.filtered,
                selectedVersion: $catalog.selected,
                installStates: catalog.installStates,
                isOnlyRelease: catalog.releaseOnly,
                canUseShortcut: !app.launch.isLaunching
            )
            .sideBarTool(
                showOnlyRelease: $catalog.releaseOnly,
                isFetchingGameVersions: Binding(
                    get: { catalog.isLoading },
                    set: { _ in }
                )
            ) {
                Task { await app.loadVersions() }
            }
            .searchable(text: $catalog.searchText, placement: .toolbar, prompt: "Filter a version")
            .onChange(of: catalog.selected) {
                guard !app.launch.isLaunching else { return }
                usernameTextFieldFocused = app.gameMode == .client
            }
            .task {
                guard catalog.versions.isEmpty else { return }
                await app.loadVersions()
            }

            if let selectedVersion = catalog.selected {
                parameters(selectedVersion: selectedVersion, settings: settings)
            }
        }
    }

    @ViewBuilder
    private func parameters(
        selectedVersion: Version,
        settings: SettingsModel
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {

            if app.java.isVisible {
                Divider()
                javaSection
            }

            Divider()

            HStack {
                Text("Game Version:")
                    .font(.headline)
                Text(selectedVersion.id)
                    .foregroundStyle(Color.accentColor)
                Spacer()
                Picker("", selection: Binding(
                    get: { app.gameMode },
                    set: { app.gameMode = $0 }
                )) {
                    ForEach(GameMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: app.gameMode) {
                    usernameTextFieldFocused = app.gameMode == .client
                }
                .disabled(app.launch.isLaunching)
            }
            .bold()

            if app.gameMode == .server {
                HStack {
                    Text("Server Core:")
                        .font(.headline)
                    Spacer()
                    Picker("", selection: Binding(
                        get: { settings.serverSoftware },
                        set: { settings.serverSoftware = $0 }
                    )) {
                        ForEach(SettingsModel.ServerSoftware.allCases) { software in
                            Text(software.rawValue).tag(software)
                        }
                    }
                    .pickerStyle(.menu)
                }
                .bold()
            }

            if app.gameMode == .client {
                HStack {
                    Text("User Name:")
                        .font(.headline)
                        .bold()
                    TextField("Input User Name", text: Binding(
                        get: { app.username },
                        set: { app.username = $0 }
                    ))
                    .foregroundStyle(Color.accentColor)
                    .bold()
                    .textFieldStyle(.plain)
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .textSelection(.disabled)
                    .focused($usernameTextFieldFocused)
                    .onSubmit { app.start() }
                    .disabled(app.launch.isLaunching)
                }
            }

            if let message = settings.memoryValidationMessage {
                Text("Invalid memory setting: \(message)")
                    .font(.caption)
                    .foregroundStyle(Color.red)
            }

            startButton
        }
        .padding([.horizontal], 10)
        .padding([.bottom], 20)
    }

    @ViewBuilder
    private var javaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Spacer()
                Text("Java Runtime (managed)")
                    .foregroundStyle(javaStatusColor)
                Spacer()
            }

            HStack {
                Text("Installed:")
                Text(app.java.installedText)
                Spacer()
                Button {
                    app.java.refresh()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .help("Rescan the managed Java runtimes under the game folder")
            }
            .foregroundStyle(Color.orange)

            HStack {
                Text("Required:")
                if let required = app.java.requiredMajor {
                    Text("\(required)")
                }
                Spacer()
                switch app.java.status {
                case .valid:
                    Label("Ready", systemImage: "checkmark.circle")
                        .foregroundStyle(Color.green)
                case .missing:
                    Label("Will be installed on launch", systemImage: "arrow.down.circle")
                        .foregroundStyle(Color.secondary)
                case .unknown:
                    EmptyView()
                }
            }
            .foregroundStyle(Color.teal)
        }
        .font(.headline)
        .bold()
    }

    /// 未安装不等于错误：启动时会按 B5 自动安装托管 JRE。
    private var javaStatusColor: Color {
        switch app.java.status {
        case .unknown: return .primary
        case .valid: return .green
        case .missing: return .orange
        }
    }

    @ViewBuilder
    private var startButton: some View {
        HStack {
            Spacer()
            Button {
                usernameTextFieldFocused = false
                app.start()
            } label: {
                HStack {
                    Text("Start \(app.gameMode.title)")
                        .font(.headline)
                        .bold()

                    if app.launch.progress.isRunning {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .controlSize(.small)
                        Text(app.launch.progress.summary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else if app.launch.progress.isFinished {
                        Image(systemName: "checkmark.seal.fill")
                            .controlSize(.regular)
                    }
                }
            }
            .tint(app.canStart ? Color.accentColor : .gray)
            .controlSize(.regular)
            .buttonStyle(.borderedProminent)
            .disabled(!app.canStart)
            .help(app.canStart
                  ? "Start \(app.gameMode.title)"
                  : "Select a version, enter a user name, and check the memory settings")
            Spacer()
        }
    }
}

#Preview {
    GameView()
        .frame(width: Constants.sidebarWidth, height: Constants.minHeight)
        .environment(AppModel())
}
