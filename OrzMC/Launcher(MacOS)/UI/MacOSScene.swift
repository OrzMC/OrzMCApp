//
//  MacOSScene.swift
//  OrzMC
//
//  Created by joker on 2024/4/28.
//

import AppKit
import Game
import SwiftUI

/// macOS 的窗口与菜单。
///
/// **单窗口**：启动器管理的是本机进程（服务端登记表、控制台缓冲、启动进度、设置），
/// 这些状态天然是“一个应用一份”。`WindowGroup` 默认允许 File > New Window，
/// 第二个窗口要么共享同一份 `AppModel`（两个窗口互相干扰选择/弹同一个错误），
/// 要么各自新建 `AppModel`（两个进程登记表写同一个 `servers.json`、重复探活、重复启动）。
/// 两种都不可接受，所以这里用 `Window`（macOS 13+）明确表达“只开一个主窗口”。
///
/// 真正需要多个窗口的场景（例如同时看两个控制台）应做成独立的 Console 窗口，
/// 而不是把整个启动器复制一份。
struct MacOSScene: Scene {

    /// 由 `OrzMCApp` 持有（App 级 `@State`），保证 Window 与 Settings 看到同一份状态。
    let app: AppModel

    var body: some Scene {
        Window("OrzMC", id: "main") {
            LauncherUI()
                .frame(minWidth: Constants.minWidth, minHeight: Constants.minHeight)
                .environment(app)
                // 单窗口 → 探活循环只有一个。周期 2s（`kill(pid, 0)`，只探自己登记过的服务端）。
                .task { await app.servers.monitor() }
        }
        .defaultSize(width: Constants.minWidth, height: Constants.minHeight)
        .defaultPosition(.center)
        .windowResizability(.contentMinSize)
        .commands {
            // 控制台窗口通过按钮 `openWindow(value:)` 打开；不需要 File > New Window
            // 这种“空白窗口”入口（会产生 nil target 的空控制台）。
            CommandGroup(replacing: .newItem) {}

            // 「关于」：系统默认项是「关于 OrzMC」，这里替换成更简洁的「关于」，
            // 仍然弹系统标准关于面板（图标 / 版本 / 版权都来自 Info.plist）。
            CommandGroup(replacing: .appInfo) {
                Button("About") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }

            // 标准的 View > Show/Hide Sidebar（⌃⌘S），由系统菜单提供。
            SidebarCommands()
            // 单窗口应用：关掉主窗口后仍可从 Window 菜单（⌘0）把它叫回来。
            MainWindowCommands()

            CommandMenu("Game") {
                // 版本列表的键盘跳转：列表聚焦时 ↑/↓ 走一格；这两个带 ⌘ 的菜单项全局可用。
                Button("Jump to Newest Version") {
                    app.catalog.stepSelection(by: -1, jumpToEdge: true)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)

                Button("Jump to Oldest Version") {
                    app.catalog.stepSelection(by: 1, jumpToEdge: true)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)

                Divider()

                Button("Start \(app.localizedGameModeTitle)") {
                    app.start()
                }
                .keyboardShortcut("b", modifiers: .command)
                .disabled(!app.canStart)

                Button("Stop All Servers…") {
                    app.wantsStopAllConfirmation = true
                }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(!app.servers.hasRunning || app.isStoppingAll)
            }

            // 帮助菜单：替换系统自动插入的「OrzMC 帮助」——本项目没有 Help Book，
            // 那一项点开只会让帮助浏览器搜不到任何结果（看起来就是“不可用”）。
            // 改成真实可用的入口：使用文档 + 联系作者。
            CommandGroup(replacing: .help) {
                if let url = URL(string: Compliance.website) {
                    Link("Documentation", destination: url)
                }
                if let url = URL(string: Compliance.contactURL) {
                    Link("Contact Author", destination: url)
                }
            }
        }

        // 控制台独立窗口：共享主窗口的 `AppModel`（同一份控制台缓冲），
        // 只是换一个视图展示；这是多窗口的安全形态。
        WindowGroup("Console", id: "console", for: ConsoleTarget.self) { $target in
            if let target {
                ConsoleWindowView(target: target)
                    .environment(app)
            }
        }
        .defaultSize(width: 760, height: 480)

        // 远程托管：独立窗口、独立 `ExarotonServerModel`。
        // 这是“多窗口”的正确形态——不是复制启动器，而是打开另一个管理面；
        // 本机进程状态仍只由主窗口的 `AppModel` 持有。
        Window("Remote Servers", id: "remote") {
            ExarotonContent()
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 900, height: 620)
        .windowResizability(.contentMinSize)

        Settings {
            // 关键修复：`SettingsView` 读的是 `AppModel`（设置只是它的一部分），
            // 这里必须注入 `AppModel`。之前只注入了 `app.settings`，打开设置页时
            // `@Environment(AppModel.self)` 找不到对象 → SIGTRAP（见 2026-10-21 崩溃报告）。
            SettingsView()
                .environment(app)
        }
    }
}

/// Window > Show Main Window（⌘0）。
///
/// `Window` 场景不会像 `WindowGroup` 那样在 File 菜单里提供 New Window；
/// 这里给一个明确的“回到主窗口”入口，避免用户关窗后只能点 Dock。
private struct MainWindowCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .windowList) {
            Button("Show Main Window") {
                openWindow(id: "main")
            }
            .keyboardShortcut("0", modifiers: .command)
        }
    }
}
