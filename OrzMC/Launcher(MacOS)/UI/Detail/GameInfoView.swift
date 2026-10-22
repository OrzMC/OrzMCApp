//
//  GameInfoView.swift
//  OrzMC
//
//  Created by joker on 2024/4/28.
//

import SwiftUI

/// 详情页：**本机实例**的启动与管理。
///
/// 远程托管（Exaroton）不再 push 进这个导航栈，而是由侧边栏的
/// “Remote Servers” 打开一个独立窗口（`MacOSScene` 的 `Window(id: "remote")`）。
/// 这样“本机实例”和“远程服务器”在信息架构上是两个平行的入口，不会让用户
/// 误以为 Exaroton 是当前版本的某个实例。
///
/// 详情页**不放工具栏**：与“当前版本”无关的入口（外部链接）已经上移到侧边栏顶部，
/// 这里只保留启动配置、实例目录与控制台。
struct GameInfoView: View {
    var body: some View {
        NavigationStack {
            BasicInfo()
        }
    }
}

#Preview {
    GameInfoView()
        .frame(width: Constants.minWidth - Constants.sidebarWidth, height: Constants.minHeight)
        .environment(AppModel())
}
