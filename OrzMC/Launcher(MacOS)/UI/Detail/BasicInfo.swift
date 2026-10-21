//
//  BasicInfo.swift
//  OrzMC
//
//  Created by joker on 2024/4/28.
//

import SwiftUI
import MojangAPI
import Game
import JokerKits
import OrzMCDesignSystem

struct FormSectionHeader: View {
    let title: String
    var deleteBtnAction: ButtonAction
    typealias ButtonAction = () -> Void
    var stopBtnAction: ButtonAction?
    /// 打开该实例自己的控制台（四种核心各一个，入口就在自己这一栏）。
    var consoleBtnAction: ButtonAction?
    var consoleIsLive: Bool = false
    var statusText: String?
    var statusDotColor: Color?
    var statusTextColor: Color?
    var body: some View {
        HStack {
            Text(title)
            if let statusText {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusDotColor ?? Color.secondary)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .foregroundStyle(statusTextColor ?? Color.secondary)
                }
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background((statusDotColor ?? Color.secondary).opacity(0.12))
                .cornerRadius(8)
                .padding(.leading, 6)
            }
            if let consoleBtnAction {
                Button(action: consoleBtnAction) {
                    Label("Console", systemImage: consoleIsLive ? "terminal.fill" : "terminal")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(consoleIsLive ? Color.green : Color.accentColor)
                .help(consoleIsLive ? "Open \(title) console (server is running)" : "Open \(title) console")
            }
            if let stopBtnAction {
                Button(action: stopBtnAction) {
                    Label("Stop", systemImage: "stop.circle")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .help("Stop \(title)")
            }
            Button(action: deleteBtnAction) {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .help("Delete \(title) files")
        }
    }
}

struct FilePathEntry: View {
    let name: String
    let path: String
    var body: some View {
        HStack {
            Text(name)
                .bold()
                .foregroundStyle(Color.accentColor)
                .padding([.trailing], 5)
            
            Text(path)
                .foregroundStyle(path.isExist() ? Color.primary : Color.red)
            
            if path.isExist() {
                Spacer()
                Button(action: {
                    _ = try? Shell.runCommand(with: ["open", "\(path)"])
                }, label: {
                    Label("Reveal in Finder", systemImage: path.isDirPath() ? "folder" : "doc.plaintext")
                        .labelStyle(.iconOnly)
                })
                .buttonStyle(.plain)
                .help("Reveal in Finder")
            }
        }
        .help(path)
    }
}
struct BasicInfo: View {

    @Environment(AppModel.self) private var app
    
    @State private var deleteTarget: DeleteTarget?
    /// 要打开控制台的实例（`版本#核心`）—— 每个服务端实例各自一个控制台。
    @State private var consoleTarget: ConsoleTarget?
    
    var body: some View {
        Group {
            if app.catalog.selected == nil {
                EmptyContentView(OrzMCContentStates.noVersionSelected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailsForm
            }
        }
        .navigationTitle(app.detailTitle)
        .navigationDestination(item: $consoleTarget) { target in
            ServerConsoleView(
                versionId: target.versionId,
                software: target.software
            )
        }
        .toolbar {
            if app.servers.hasRunning {
                ToolbarItem {
                    Button {
                        app.stopAllServers()
                    } label: {
                        Label("Stop All Servers", systemImage: "stop.circle")
                    }
                    .keyboardShortcut(.init(.init("k")), modifiers: .command)
                    .help("Stop all running Minecraft servers")
                }
            }
        }
        .confirmationDialog(
            deleteTarget?.confirmationTitle ?? "Delete Files?",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            presenting: deleteTarget
        ) { target in
            Button("Delete", role: .destructive) {
                try? target.path.remove()
                // 该实例的文件没了 → 它的控制台日志/历史也一并清掉。
                if case let .server(software, _) = target,
                   let versionId = app.catalog.selected?.id {
                    app.removeConsole(versionId: versionId, software: software)
                }
                app.catalog.refreshInstallStates()
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) {
                deleteTarget = nil
            }
        } message: { target in
            Text("This removes files at \(target.path). This action cannot be undone.")
        }
    }

    private var detailsForm: some View {
        Form {
            // 四种核心（Vanilla/Paper/Fabric/Forge）同一份渲染：只显示已存在的目录，
            // 插件目录仅 Paper 有（引擎 `GamePlan.serverPluginDir` 仅对 paper 有意义）。
            ForEach(SettingsModel.ServerSoftware.allCases) { software in
                if let serverDirPath = serverDirPath(for: software), serverDirPath.isExist() {
                    let status = statusFor(software: software)
                    Section {
                        FilePathEntry(
                            name: "Game",
                            path: serverDirPath
                        )
                        if software.supportsPlugins,
                           let pluginDirPath = serverPluginDirPath(for: software) {
                            FilePathEntry(
                                name: "Plugins",
                                path: pluginDirPath
                            )
                            if let pluginUpdateDirPath = serverPluginUpdateDirPath(for: software) {
                                VStack(alignment: .leading) {
                                    FilePathEntry(
                                        name: "PluginsUpdate",
                                        path: pluginUpdateDirPath
                                    )
                                    .onLongPressGesture {
                                        Task {
                                            try await app.downloadAllServerPlugins()
                                        }
                                    }
                                    if (app.plugins.isDownloading) {
                                        HStack {
                                            Text(app.plugins.title)
                                            Spacer()
                                            ProgressView(value: app.plugins.progress)
                                                .progressViewStyle(.linear)
                                        }
                                    }
                                }
                            }
                        }
                    } header: {
                        FormSectionHeader(
                            title: "Server (\(software.rawValue))",
                            deleteBtnAction: {
                                deleteTarget = .server(software: software, path: serverDirPath)
                            },
                            stopBtnAction: stopActionFor(software: software),
                            consoleBtnAction: {
                                if let selectedVersion = app.catalog.selected {
                                    consoleTarget = ConsoleTarget(
                                        versionId: selectedVersion.id,
                                        software: software
                                    )
                                }
                            },
                            consoleIsLive: app.isConsoleAttached(
                                versionId: app.catalog.selected?.id ?? "",
                                software: software
                            ),
                            statusText: status.text,
                            statusDotColor: status.dotColor,
                            statusTextColor: status.textColor
                        )
                    }
                }
            }

            if let clientDirPath, clientDirPath.isExist() {
                Section {
                    FilePathEntry(
                        name: "Game",
                        path: clientDirPath
                    )
                } header: {
                    FormSectionHeader(title: "Client") {
                        deleteTarget = .client(path: clientDirPath)
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// 控制台要打开的实例（`Identifiable` 供 `navigationDestination(item:)` 用）。
struct ConsoleTarget: Identifiable, Hashable {
    let versionId: String
    let software: SettingsModel.ServerSoftware
    var id: String { "\(versionId)#\(software.rawValue)" }
}

private extension BasicInfo {
    enum DeleteTarget: Identifiable {
        case server(software: SettingsModel.ServerSoftware, path: String)
        case client(path: String)

        var id: String { path }

        var path: String {
            switch self {
            case let .server(_, path), let .client(path):
                path
            }
        }

        var confirmationTitle: String {
            switch self {
            case let .server(software, _):
                "Delete \(software.rawValue) Server Files?"
            case .client:
                "Delete Client Files?"
            }
        }
    }
}

extension BasicInfo {

    func statusFor(software: SettingsModel.ServerSoftware) -> (text: String, dotColor: Color, textColor: Color) {
        guard let selectedVersion = app.catalog.selected
        else {
            return ("Unknown", .secondary, .secondary)
        }
        let running = app.servers.isRunning(versionId: selectedVersion.id, software: software)
        if running {
            return ("Running", .green, .green)
        }
        return ("Stopped", .red, .secondary)
    }
    
    func stopActionFor(software: SettingsModel.ServerSoftware) -> FormSectionHeader.ButtonAction? {
        guard let selectedVersion = app.catalog.selected,
              app.servers.isRunning(versionId: selectedVersion.id, software: software)
        else {
            return nil
        }
        return {
            app.stopServer(software: software)
        }
    }
    
    func serverDirPath(for software: SettingsModel.ServerSoftware) -> String? {
        guard let selectedVersion = app.catalog.selected
        else {
            return nil
        }
        return GamePlan.serverDir(version: selectedVersion.id, type: software.gameType)
    }

    func serverPluginDirPath(for software: SettingsModel.ServerSoftware) -> String? {
        guard let selectedVersion = app.catalog.selected
        else {
            return nil
        }
        return GamePlan.serverPluginDir(version: selectedVersion.id, type: software.gameType)
    }

    func serverPluginUpdateDirPath(for software: SettingsModel.ServerSoftware) -> String? {
        guard let selectedVersion = app.catalog.selected
        else {
            return nil
        }
        return GamePlan.serverPluginUpdateDir(version: selectedVersion.id, type: software.gameType)
    }
    
    var clientDirPath: String? {
        guard let selectedVersion = app.catalog.selected
        else {
            return nil
        }
        return GamePlan.clientDir(version: selectedVersion.id)
    }
}


#Preview {
    
    @Previewable
    @State
    var app = AppModel()

    BasicInfo()
        .frame(width: Constants.minWidth - Constants.sidebarWidth, height: Constants.minHeight)
        .environment(app)
}
