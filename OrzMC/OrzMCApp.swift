//
//  OrzMCApp.swift
//  OrzMC
//
//  Created by joker on 2022/10/18.
//

import SwiftUI
#if canImport(OrzAppUpdater)
import OrzAppUpdater
#endif

@main
struct OrzMCApp: App {

#if os(macOS)
    /// 整个 macOS 应用**唯一**的组合根：主窗口与 Settings 共享同一份状态。
    @State private var app = AppModel()
#endif

#if canImport(OrzAppUpdater)
    let updaterController = OrzAppUpdaterController()
#endif
    init() {
#if DEBUG && os(macOS)
        // UI 复审用：`--snapshot <前缀>` 时渲染自己的窗口并退出（不需要屏幕录制权限）。
        WindowSnapshot.runIfRequested()
#endif
    }

    var body: some Scene {
#if os(macOS)
        MacOSScene(app: app)
            .addCheckUpdatesCommand(updaterController: updaterController)
#elseif os(iOS)
        WindowGroup {
            ContentView()
        }
#endif
    }
}
