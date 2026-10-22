//
//  LauncherUI.swift
//  OrzMC
//
//  Created by joker on 2022/10/19.
//

import SwiftUI

/// 主界面：左侧版本/启动表单，右侧详情。**只做布局**，逻辑在 `AppModel`。
struct LauncherUI: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        NavigationSplitView {
            GameView()
                // 侧边栏可自由伸缩：窄到 260 仍放得下"图标 + 版本号 + 副标题"，宽到 520 也不散。
                .navigationSplitViewColumnWidth(min: 260, ideal: Constants.sidebarWidth, max: 520)
        } detail: {
            GameInfoView()
        }
        .navigationSplitViewStyle(.prominentDetail)
        .alert(
            "Operation Failed",
            isPresented: Binding(
                get: { app.error != nil },
                set: { if !$0 { app.error = nil } }
            )
        ) {
            Button("OK", role: .cancel) { app.error = nil }
        } message: {
            // 文案 + 规范错误码（`E_VERIFY` 之类），便于用户搜索/上报。
            Text(app.error?.description ?? "")
        }
        // 「停止全部」的唯一确认入口：菜单和详情页工具栏都只设置这个标志，
        // 避免同一个快捷键注册两个 alert（以前 Game 菜单和工具栏各有一个 ⌘K）。
        .alert(
            "Stop All Servers?",
            isPresented: Binding(
                get: { app.wantsStopAllConfirmation },
                set: { app.wantsStopAllConfirmation = $0 }
            )
        ) {
            Button("Stop All (graceful)") {
                app.wantsStopAllConfirmation = false
                app.stopAllServers()
            }
            Button("Terminate All", role: .destructive) {
                app.wantsStopAllConfirmation = false
                app.terminateAllServers()
            }
            Button("Cancel", role: .cancel) {
                app.wantsStopAllConfirmation = false
            }
        } message: {
            Text(
                """
                Stop All sends `stop` to every running server, so each one saves and exits normally. \
                Servers started by a previous app session have no console to talk to — those are left alone.

                Terminate All kills the processes instead (SIGTERM, then SIGKILL). Recent world changes may be lost.
                """
            )
        }
    }
}

#Preview {
    LauncherUI()
        .frame(minWidth: Constants.minWidth, minHeight: Constants.minHeight)
        .environment(AppModel())
}
