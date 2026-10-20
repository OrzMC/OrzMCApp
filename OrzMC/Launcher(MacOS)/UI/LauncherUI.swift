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
                .navigationSplitViewColumnWidth(Constants.sidebarWidth)
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
    }
}

#Preview {
    LauncherUI()
        .frame(minWidth: Constants.minWidth, minHeight: Constants.minHeight)
        .environment(AppModel())
}
