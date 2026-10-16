//
//  MacOSScene.swift
//  OrzMC
//
//  Created by joker on 2024/4/28.
//

import AppKit
import Game
import SwiftUI

struct MacOSScene: Scene {
    
    @State private var model = GameModel()
    
    var body: some Scene {
        WindowGroup("OrzMC", id: "macos") {
            LauncherUI()
                .frame(minWidth: Constants.minWidth, minHeight: Constants.minHeight)
                .environment(model)
        }
        .defaultSize(width: Constants.minWidth, height: Constants.minHeight)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Game") {
                Button("Start \(model.gameType.rawValue.capitalized)") {
                    model.startGame()
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!model.canStartGame)

                Button("Stop All Servers") {
                    model.stopAllRunningServer()
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!model.isShowKillAllServerButton)
            }

            CommandGroup(after: .help) {
                Button("Contact Author") {
                    if let url = URL(string: "mailto:\(Compliance.contactEmail)") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
        
        Settings {
            SettingsView()
                .environment(model.settingsModel)
        }
    }
}
