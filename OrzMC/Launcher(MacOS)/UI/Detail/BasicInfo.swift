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

    @Environment(GameModel.self) private var model
    
    @State private var deleteTarget: DeleteTarget?

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        Group {
            if model.selectedVersion == nil {
                EmptyContentView(OrzMCContentStates.noVersionSelected)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                detailsForm
            }
        }
        .navigationTitle(model.detailTitle)
        .onReceive(timer) { _ in
            model.checkRunningServer()
        }
        .toolbar {
            if model.isShowKillAllServerButton {
                ToolbarItem {
                    Button {
                        model.stopAllRunningServer()
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
            let paperStatus = statusFor(software: .paper)
            let vanillaStatus = statusFor(software: .vanilla)
            let paperStopAction = stopActionFor(software: .paper)
            let vanillaStopAction = stopActionFor(software: .vanilla)

            if let paperServerDirPath, paperServerDirPath.isExist() {
                Section {
                    FilePathEntry(
                        name: "Game",
                        path: paperServerDirPath
                    )
                    if let paperServerPluginDirPath {
                        FilePathEntry(
                            name: "Plugins",
                            path: paperServerPluginDirPath
                        )
                        if let paperServerPluginUpdateDirPath {
                            VStack(alignment: .leading) {
                                FilePathEntry(
                                    name: "PluginsUpdate",
                                    path: paperServerPluginUpdateDirPath
                                )
                                .onLongPressGesture {
                                    Task {
                                        try await model.downloadAllServerPlugins()
                                    }
                                }
                                if (model.serverPluginDownloadProgress > 0) {
                                    HStack {
                                        Text(model.serverPluginDownloadProgressTitle)
                                        Spacer()
                                        ProgressView(value: model.serverPluginDownloadProgress)
                                            .progressViewStyle(.linear)
                                    }
                                        
                                }
                            }
                        }
                    }
                } header: {
                    FormSectionHeader(
                        title: "Server (Paper)",
                        deleteBtnAction: {
                            deleteTarget = .paper(path: paperServerDirPath)
                        },
                        stopBtnAction: paperStopAction,
                        statusText: paperStatus.text,
                        statusDotColor: paperStatus.dotColor,
                        statusTextColor: paperStatus.textColor
                    )
                }
            }

            if let vanillaServerDirPath, vanillaServerDirPath.isExist() {
                Section {
                    FilePathEntry(
                        name: "Game",
                        path: vanillaServerDirPath
                    )
                } header: {
                    FormSectionHeader(
                        title: "Server (Vanilla)",
                        deleteBtnAction: {
                            deleteTarget = .vanilla(path: vanillaServerDirPath)
                        },
                        stopBtnAction: vanillaStopAction,
                        statusText: vanillaStatus.text,
                        statusDotColor: vanillaStatus.dotColor,
                        statusTextColor: vanillaStatus.textColor
                    )
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

private extension BasicInfo {
    enum DeleteTarget: Identifiable {
        case paper(path: String)
        case vanilla(path: String)
        case client(path: String)

        var id: String { path }

        var path: String {
            switch self {
            case let .paper(path), let .vanilla(path), let .client(path):
                path
            }
        }

        var confirmationTitle: String {
            switch self {
            case .paper:
                "Delete Paper Server Files?"
            case .vanilla:
                "Delete Vanilla Server Files?"
            case .client:
                "Delete Client Files?"
            }
        }
    }
}

extension BasicInfo {

    func statusFor(software: SettingsModel.ServerSoftware) -> (text: String, dotColor: Color, textColor: Color) {
        guard let selectedVersion = model.selectedVersion
        else {
            return ("Unknown", .secondary, .secondary)
        }
        let running = model.isServerRunning(versionId: selectedVersion.id, software: software)
        if running {
            return ("Running", .green, .green)
        }
        return ("Stopped", .red, .secondary)
    }
    
    func stopActionFor(software: SettingsModel.ServerSoftware) -> FormSectionHeader.ButtonAction? {
        guard let selectedVersion = model.selectedVersion,
              model.isServerRunning(versionId: selectedVersion.id, software: software)
        else {
            return nil
        }
        return {
            model.stopServer(versionId: selectedVersion.id, software: software)
        }
    }
    
    var paperServerDirPath: String? {
        guard let selectedVersion = model.selectedVersion
        else {
            return nil
        }
        return GamePlan.serverDir(version: selectedVersion.id, type: .paper)
    }
    
    var paperServerPluginDirPath: String? {
        guard let selectedVersion = model.selectedVersion
        else {
            return nil
        }
        return GamePlan.serverPluginDir(version: selectedVersion.id, type: .paper)
    }
    
    var paperServerPluginUpdateDirPath: String? {
        guard let selectedVersion = model.selectedVersion
        else {
            return nil
        }
        return GamePlan.serverPluginUpdateDir(version: selectedVersion.id, type: .paper).dirPath
    }
    
    var vanillaServerDirPath: String? {
        guard let selectedVersion = model.selectedVersion
        else {
            return nil
        }
        return GamePlan.serverDir(version: selectedVersion.id, type: .vanilla)
    }
    
    var clientDirPath: String? {
        guard let selectedVersion = model.selectedVersion
        else {
            return nil
        }
        return GamePlan.clientDir(version: selectedVersion.id)
    }
}


#Preview {
    
    @Previewable
    @State
    var gameModel = GameModel()
    
    BasicInfo()
        .frame(width: Constants.minWidth - Constants.sidebarWidth, height: Constants.minHeight)
        .environment(gameModel)
}
