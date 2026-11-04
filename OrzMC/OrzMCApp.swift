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

#if DEBUG && os(iOS)
    /// 手势 UI 用例使用独立偏好域，避免覆盖真机用户的字号和换行设置。
    private let uiTestDefaults: UserDefaults? = {
        guard ProcessInfo.processInfo.environment["ORZMC_DEMO_ISOLATE_DEFAULTS"] == "1" else { return nil }
        let suite = "com.joker.OrzMC.console-ui-tests"
        guard let defaults = UserDefaults(suiteName: suite) else {
            preconditionFailure("Unable to isolate console UI test preferences")
        }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }()
#endif

#if os(macOS)
    /// 整个 macOS 应用**唯一**的组合根：主窗口与 Settings 共享同一份状态。
    @State private var app = AppModel()

    /// 快捷键（用户可改，设置页「快捷键」页读写它）。
    @State private var shortcuts = ShortcutStore()
#endif

#if canImport(OrzAppUpdater)
    let updaterController = OrzAppUpdaterController()
#endif
    init() {
#if DEBUG && os(macOS)
        // UI 复审用：`--snapshot <前缀>` 时渲染自己的窗口并退出（不需要屏幕录制权限）。
        WindowSnapshot.runIfRequested()
#endif
#if DEBUG
        // 无界面验收：`ORZMC_DEMO_MCSM_DIAGNOSE=1` 时拉一遍所有 MCSM 面板、写诊断文件后退出。
        if MCSManagerDiagnose.isRequested {
            Task { @MainActor in await MCSManagerDiagnose.runIfRequested() }
        }
#endif
    }

    var body: some Scene {
#if os(macOS)
        MacOSScene(app: app, shortcuts: shortcuts)
            // 标题由应用提供（依赖里的默认值是硬编码英文）；`String(localized:)` 走应用自己的
            // Localizable.xcstrings，中文界面显示「检查更新…」。
            .addCheckUpdatesCommand(
                updaterController: updaterController,
                title: String(localized: "Check for Updates…")
            )
#elseif os(iOS)
        WindowGroup {
            ContentView()
#if DEBUG
                .defaultAppStorage(uiTestDefaults ?? .standard)
#endif
        }
#endif
    }
}
