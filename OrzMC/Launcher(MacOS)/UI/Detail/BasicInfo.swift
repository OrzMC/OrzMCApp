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
import OrzMCLauncher

struct FormSectionHeader: View {
    typealias ButtonAction = () -> Void

    let title: String
    /// 运行状态（服务端/客户端都有：Running / Stopped / Unknown）。
    var statusText: String?
    var statusDotColor: Color?
    var statusTextColor: Color?
    /// 该实例有操作在进行（删除/停止/启动中）→ **全部按钮禁用**，防连点。
    var isBusy: Bool = false
    /// 打开该实例自己的控制台（客户端 + 四种核心各一个，入口就在自己这一栏）。
    var consoleBtnAction: ButtonAction?
    var consoleIsLive: Bool = false
    /// 停止（高危：会杀进程）——点击后需二次确认。
    var stopBtnAction: ButtonAction?
    /// 删除（**高危**：删文件，不可恢复）——点击后需二次确认。
    var deleteBtnAction: ButtonAction

    var body: some View {
        HStack(spacing: 8) {
            // 左：标题 + 状态
            Text(title)
            if let statusText {
                statusBadge(statusText)
            }

            Spacer(minLength: 12)

            // 右：操作按钮（高危动作带确认，执行中全禁用）
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            }
            HStack(spacing: 10) {
                if let consoleBtnAction {
                    Button(action: consoleBtnAction) {
                        Label("Console", systemImage: consoleIsLive ? "terminal.fill" : "terminal")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(consoleIsLive ? Color.green : Color.accentColor)
                    .help(consoleIsLive ? "Open \(title) console (running)" : "Open \(title) console")
                }
                if let stopBtnAction {
                    Button(action: stopBtnAction) {
                        Label("Stop", systemImage: "stop.circle")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.orange)
                    .help("Stop \(title) (asks for confirmation)")
                }
                Button(action: deleteBtnAction) {
                    Label("Delete", systemImage: "trash")
                        .labelStyle(.iconOnly)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .help("Delete \(title) files (asks for confirmation — cannot be undone)")
            }
            .disabled(isBusy)
        }
    }

    private func statusBadge(_ text: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusDotColor ?? Color.secondary)
                .frame(width: 6, height: 6)
            Text(text)
                .foregroundStyle(statusTextColor ?? Color.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background((statusDotColor ?? Color.secondary).opacity(0.12))
        .cornerRadius(8)
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
    
    /// 待确认的高危操作（删除/停止）——统一入口，点按钮只"排队"，确认后才执行。
    @State private var pendingRisky: RiskyAction?
    /// 正在执行的实例（`版本#实例`）→ 该实例按钮全禁用（防连点）。
    @State private var busyInstanceId: String?
    /// 「停止全部」的二次确认。
    @State private var confirmStopAll = false
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
            consoleView(for: target)
        }
        .toolbar {
            if app.servers.hasRunning {
                ToolbarItem {
                    Button {
                        // 会断开所有在线玩家 → 二次确认；执行中禁用（防连点）。
                        confirmStopAll = true
                    } label: {
                        Label("Stop All Servers", systemImage: "stop.circle")
                    }
                    .keyboardShortcut(.init(.init("k")), modifiers: .command)
                    .disabled(busyInstanceId != nil)
                    .help("Stop all running Minecraft servers (asks for confirmation)")
                }
            }
        }
        .alert("Stop All Servers?", isPresented: $confirmStopAll) {
            Button("Stop All", role: .destructive) {
                busyInstanceId = "all"
                Task { @MainActor in
                    defer { busyInstanceId = nil }
                    app.stopAllServers()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All running servers receive `stop` and shut down. Players on them will be disconnected.")
        }
        .alert(
            pendingRisky?.confirmTitle ?? "",
            isPresented: Binding(
                get: { pendingRisky != nil },
                set: { if !$0 { pendingRisky = nil } }
            ),
            presenting: pendingRisky
        ) { action in
            Button(action.confirmButtonTitle, role: action.isDestructive ? .destructive : nil) {
                perform(action)
            }
            Button("Cancel", role: .cancel) { pendingRisky = nil }
        } message: { action in
            Text(action.message(selectedVersionId: app.catalog.selected?.id))
        }
    }

    /// 执行已确认的高危操作：期间该实例按钮全禁用（防连点），完成后复位。
    private func perform(_ action: RiskyAction) {
        let instanceId = action.instanceId
        guard busyInstanceId == nil else { return }
        busyInstanceId = instanceId
        pendingRisky = nil

        Task { @MainActor in
            defer { busyInstanceId = nil }
            switch action {
            case let .deleteServer(versionId, software, path):
                try? path.remove()
                app.removeConsole(versionId: versionId, software: software)
                app.catalog.refreshInstallStates()
            case let .deleteClient(versionId, path):
                try? path.remove()
                app.removeClientConsole(versionId: versionId)
                app.catalog.refreshInstallStates()
            case let .stopServer(versionId, software):
                app.stopServer(versionId: versionId, software: software)
            }
        }
    }

    /// 该服务端实例是否有操作在进行。
    private func isBusy(software: SettingsModel.ServerSoftware) -> Bool {
        let key = "\(app.catalog.selected?.id ?? "")#\(software.rawValue)"
        return busyInstanceId == key
    }

    /// 客户端运行状态：以"客户端控制台是否挂着进程"为准（进程退出即解绑）。
    private var clientRunStatus: (text: String, dotColor: Color, textColor: Color) {
        guard let versionId = app.catalog.selected?.id else {
            return ("Unknown", .secondary, .secondary)
        }
        return app.isClientConsoleAttached(versionId: versionId)
            ? ("Running", .green, .green)
            : ("Stopped", .red, .secondary)
    }

    private func consoleView(for target: ConsoleTarget) -> some View {
        let console: ServerConsoleModel = app.console(for: target)
        let title: String = target.title
        return ServerConsoleView(title: title, console: console)
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
                            statusText: status.text,
                            statusDotColor: status.dotColor,
                            statusTextColor: status.textColor,
                            isBusy: isBusy(software: software),
                            consoleBtnAction: {
                                guard let versionId = app.catalog.selected?.id else { return }
                                consoleTarget = ConsoleTarget(versionId: versionId, software: software)
                            },
                            consoleIsLive: app.isConsoleAttached(
                                versionId: app.catalog.selected?.id ?? "",
                                software: software
                            ),
                            stopBtnAction: stopActionFor(software: software),
                            deleteBtnAction: {
                                guard let versionId = app.catalog.selected?.id else { return }
                                pendingRisky = .deleteServer(
                                    versionId: versionId,
                                    software: software,
                                    path: serverDirPath
                                )
                            }
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
                    let clientStatus = clientRunStatus
                    FormSectionHeader(
                        title: "Client",
                        statusText: clientStatus.text,
                        statusDotColor: clientStatus.dotColor,
                        statusTextColor: clientStatus.textColor,
                        isBusy: busyInstanceId == "\(app.catalog.selected?.id ?? "")#Client",
                        consoleBtnAction: {
                            guard let versionId = app.catalog.selected?.id else { return }
                            consoleTarget = ConsoleTarget(versionId: versionId, software: nil)
                        },
                        consoleIsLive: app.isClientConsoleAttached(
                            versionId: app.catalog.selected?.id ?? ""
                        ),
                        deleteBtnAction: {
                            guard let versionId = app.catalog.selected?.id else { return }
                            pendingRisky = .deleteClient(versionId: versionId, path: clientDirPath)
                        }
                    )
                }
            }
        }
        .formStyle(.grouped)
    }
}

/// 控制台要打开的实例（`Identifiable` 供 `navigationDestination(item:)` 用）。
///
/// `software == nil` 表示**客户端实例**（`版本#Client`）；否则是对应的服务端核心。
struct ConsoleTarget: Identifiable, Hashable {
    let versionId: String
    let software: SettingsModel.ServerSoftware?

    var id: String {
        "\(versionId)#\(software?.rawValue ?? "Client")"
    }

    var title: String {
        "\(versionId) \(software?.rawValue ?? "Client")"
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
            // 停止会断开在线玩家 → 也要二次确认。
            pendingRisky = .stopServer(versionId: selectedVersion.id, software: software)
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
