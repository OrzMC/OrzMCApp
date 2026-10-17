//
//  GameView.swift
//  OrzMC
//
//  Created by joker on 4/26/24.
//

import SwiftUI
import MojangAPI
import Game

struct GameView: View {
    
    @State private var searchContent: String = ""
    
    @State private var filteredVersions = [Version]()
    
    @State private var showOnlyRelease: Bool = true
    
    @FocusState private var usernameTextFieldFocused: Bool
    
    @Environment(GameModel.self) private var model

    private let versionFilterService = VersionFilterService()
    
    var body: some View {
        @Bindable var model = model
        @Bindable var settings = model.settingsModel
        VStack(alignment: .leading) {
            GameList(
                versions: $filteredVersions,
                selectedVersion: $model.selectedVersion,
                isOnlyRelease: showOnlyRelease,
                canUseShortcut: !model.isLaunchingGame
            )
            .sideBarTool(
                showOnlyRelease: $showOnlyRelease,
                isFetchingGameVersions: $model.isFetchingGameVersions
            ) {
                reloadList()
            }
            .searchable(text: $searchContent, placement: .toolbar, prompt: "Filter a version")
            .onChange(of: searchContent) {
                refreshList()
            }
            .onChange(of: showOnlyRelease) {
                refreshList()
            }
            .onChange(of: model.selectedVersion, {
                guard !model.isLaunchingGame else { return }
                usernameTextFieldFocused = model.isClient
            })
            .onAppear {
                guard model.versions.isEmpty
                else {
                    return
                }
                reloadList()
            }
            
            if let selectedVersion = model.selectedVersion {
                VStack(alignment: .leading, spacing: 10) {
                    
                    if model.showJavaVersionArea {
                        Divider()
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Spacer()
                                Text("Java Runtime (managed)")
                                    .foregroundStyle(model.javaVersionTextColor)
                                Spacer()
                            }

                            HStack {
                                Text("Installed:")
                                Text(model.installedJavaVersionsText)
                                Spacer()
                                Button {
                                    model.refreshJavaRuntimes()
                                } label: {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                }
                                .help("Rescan the managed Java runtimes under the game folder")
                            }
                            .foregroundStyle(Color.orange)

                            HStack {
                                Text("Required:")
                                if let requiredJavaMajorVersion = model.selectedGameJavaMajorVersionRequired {
                                    Text("\(requiredJavaMajorVersion)")
                                }
                                Spacer()
                                switch model.javaRuntimeStatus {
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
                    
                    Divider()
                    HStack() {
                        Text("Game Version:")
                            .font(.headline)
                        
                        Text(selectedVersion.id)
                            .foregroundStyle(Color.accentColor)
                        
                        Spacer()
                        
                        Picker("", selection: $model.gameType) {
                            ForEach(GameModel.GameType.allCases, id: \.self.rawValue) { type in
                                Text(type.rawValue)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.menu)
                        .onChange(of: model.gameType) {
                            usernameTextFieldFocused = model.isClient
                        }
                        .disabled(model.isLaunchingGame)
                    }
                    .bold()
                    
                    if model.isServer {
                        HStack {
                            Text("Server Core:")
                                .font(.headline)
                            Spacer()
                            Picker("", selection: $settings.serverSoftware) {
                                ForEach(SettingsModel.ServerSoftware.allCases) { software in
                                    Text(software.rawValue).tag(software)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                        .bold()
                    }
                    
                    if model.isClient {
                        HStack() {
                            Text("User Name:")
                                .font(.headline)
                                .bold()
                            TextField("Input User Name", text: $model.username)
                                .foregroundStyle(Color.accentColor)
                                .bold()
                                .textFieldStyle(.plain)
                                .textContentType(.username)
                                .autocorrectionDisabled()
                                .textSelection(.disabled)
                                .focused($usernameTextFieldFocused)
                                .onSubmit {
                                    startGame()
                                }
                                .disabled(model.isLaunchingGame)
                        }
                    }
                    
                    HStack() {
                        Spacer()
                        Button {
                            startGame()
                        } label: {
                            HStack {
                                Text("Start \(model.gameType.rawValue.capitalized)")
                                    .font(.headline)
                                    .bold()
                                
                                if (model.progress > 0 && model.progress < 1) || model.progressIsIndefinite {
                                    if model.progressIsIndefinite {
                                        ProgressView()
                                            .progressViewStyle(.circular)
                                            .controlSize(.small)
                                    } else {
                                        ProgressView(value: model.progress, total: 1)
                                            .progressViewStyle(.circular)
                                            .controlSize(.small)
                                    }
                                    Text(model.progressDesc)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                } else if model.progress >= 1 {
                                    Image(systemName: "checkmark.seal.fill")
                                        .controlSize(.regular)
                                }
                            }
                        }
                        .tint(model.canStartGame ? Color.accentColor : .gray)
                        .controlSize(.regular)
                        .buttonStyle(.borderedProminent)
                        .disabled(!model.canStartGame)
                        .help(model.canStartGame ? "Start \(model.gameType.rawValue)" : "Select a version and enter a user name to start")
                        Spacer()
                    }
                }
                .padding([.horizontal], 10)
                .padding([.bottom], 20)
            }
        }
    }
}

extension GameView {
    
    func startGame() {
        guard model.canStartGame
        else {
            return
        }
        usernameTextFieldFocused = false
        model.startGame()
    }
    
    func reloadList() {
        Task {
            model.isFetchingGameVersions = true
            defer {
                model.isFetchingGameVersions = false
            }
            do {
                try await model.fetchGameVersions()
            } catch {
                model.errorMessage = "Failed to fetch game versions: \(error.localizedDescription)"
            }
            refreshList()
        }
    }
    
    @MainActor
    func refreshList() {
        filteredVersions = versionFilterService.filter(
            versions: model.versions,
            searchText: searchContent,
            releaseOnly: showOnlyRelease
        )
        
        if model.selectedVersion == nil {
            model.selectedVersion = filteredVersions.first
        }
    }
}

#Preview {
    GameView()
        .frame(width: Constants.sidebarWidth, height: Constants.minHeight)
        .environment(GameModel())
}
