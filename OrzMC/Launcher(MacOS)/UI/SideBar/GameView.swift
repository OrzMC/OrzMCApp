//
//  GameView.swift
//  OrzMC
//
//  Created by joker on 4/26/24.
//

import SwiftUI
import MojangAPI
import Game
import JokerKits

struct GameView: View {
    
    @State private var searchContent: String = ""
    
    @State private var filteredVersions = [Version]()
    
    @State private var showOnlyRelease: Bool = true
    
    @FocusState private var usernameTextFieldFocused: Bool
    
    @State private var enableStartGameButton: Bool = false
    
    @State private var downloadingJDK: Bool = false
    
    @State private var downloadJDKProgress: Double = 0
    
    @State private var downloadJDKCompleted: Bool = false
    
    @State private var jdkFileURL: URL? = nil
    
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
                                Text("Java Version")
                                    .foregroundStyle(model.javaVersionTextColor)
                                Spacer()
                            }
                            
                            HStack {
                                Text("Current:")
                                if let currentJavaMajorVersion = model.currentJavaMajorVersion {
                                    Text("\(currentJavaMajorVersion)")
                                } else {
                                    Spacer()
                                    Button {
                                        model.fetchCurrentJavaMajorVersion()
                                    } label: {
                                        Image(systemName: "arrow.triangle.2.circlepath")
                                    }
                                }
                            }
                            .foregroundStyle(Color.orange)
                            
                            HStack {
                                Text("Required:")
                                if let requiredJavaMajorVersion = model.selectedGameJavaMajorVersionRequired {
                                    Text("\(requiredJavaMajorVersion)")
                                }
                                if model.javaRuntimeStatus != .valid, let javaVersionInt = model.selectedGameJavaMajorVersionRequired  {
                                    Spacer()
                                    Button {
                                        Task {
                                            if let jdkFilePath = jdkFileURL?.path() {
                                                downloadJDKCompleted = FileManager.default.fileExists(atPath: jdkFilePath)
                                                if downloadJDKCompleted {
                                                    await Shell.runCommand(with: ["open", "\(jdkFilePath)"])
                                                    return
                                                }
                                            }
                                            
                                            do {
                                                downloadingJDK = true
                                                defer {
                                                    downloadingJDK = false
                                                }
                                                let javaVersion = String(javaVersionInt)
                                                jdkFileURL = try await OracleJava.downloadJDK(javaVersion) { progress in
                                                    await MainActor.run {
                                                        downloadJDKProgress = progress * 100
                                                    }
                                                }

                                                if let jdkFilePath = jdkFileURL?.path() {
                                                    downloadJDKCompleted = FileManager.default.fileExists(atPath: jdkFilePath)
                                                } else {
                                                    downloadJDKCompleted = false
                                                }
                                            } catch {
                                                downloadJDKCompleted = false
                                                model.errorMessage = "Failed to download JDK: \(error.localizedDescription)"
                                            }
                                        }
                                        
                                    } label: {
                                        Label(downloadingJDK ? String(format: "%.2f %%", downloadJDKProgress) : "\(downloadJDKCompleted ? "Install" : "Download") JDK", systemImage: downloadJDKCompleted ? "folder" : "arrow.down.circle")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(downloadingJDK)
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
                            refreshStartGameButton()
                        }
                        .onChange(of: usernameTextFieldFocused) {
                            refreshStartGameButton()
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
                                .onChange(of: model.username) {
                                    refreshStartGameButton()
                                }
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
                                
                                if (model.progress > 0 && model.progress < 1) {
                                    ProgressView(value: model.progress, total: 1)
                                        .progressViewStyle(.circular)
                                        .controlSize(.small)
                                    Text(model.progressDesc)
                                } else if model.progress >= 1 {
                                    Image(systemName: "checkmark.seal.fill")
                                        .controlSize(.regular)
                                }
                            }
                        }
                        .tint(enableStartGameButton ? Color.accentColor : .gray)
                        .controlSize(.regular)
                        .buttonStyle(.borderedProminent)
                        .disabled(!enableStartGameButton)
                        .keyboardShortcut(.init(.init("b")), modifiers: .command)
                        Spacer()
                    }
                }
                .padding([.horizontal], 10)
                .padding([.bottom], 20)
                .onChange(of: model.isLaunchingGame) {
                    refreshStartGameButton()
                }
            }
        }
    }
}

extension GameView {
    
    func startGame() {
        guard enableStartGameButton
        else {
            return
        }
        usernameTextFieldFocused = false
        model.startGame()
    }
    
    func refreshStartGameButton() {
        guard model.selectedVersion != nil
        else {
            enableStartGameButton = false
            return
        }
        enableStartGameButton = !model.isFetchingGameVersions && !model.isLaunchingGame
        if model.isClient {
            enableStartGameButton = !model.username.isEmpty && enableStartGameButton
        }
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
