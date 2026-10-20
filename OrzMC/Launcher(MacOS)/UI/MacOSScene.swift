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

    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup("OrzMC", id: "macos") {
            LauncherUI()
                .frame(minWidth: Constants.minWidth, minHeight: Constants.minHeight)
                .environment(app)
                // 周期探活（2s，`kill(pid, 0)`；只探自己登记过的服务端）。
                .task { await app.servers.monitor() }
        }
        .defaultSize(width: Constants.minWidth, height: Constants.minHeight)
        .windowResizability(.contentMinSize)
        .commands {
            CommandMenu("Game") {
                Button("Start \(app.gameMode.title)") {
                    app.start()
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!app.canStart)

                Button("Stop All Servers") {
                    app.stopAllServers()
                }
                .keyboardShortcut("k", modifiers: .command)
                .disabled(!app.servers.hasRunning)
            }

            CommandGroup(after: .help) {
                Button("Contact Author") {
                    if let url = URL(string: Compliance.contactURL) {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }

        Settings {
            SettingsView()
                .environment(app.settings)
        }
    }
}
