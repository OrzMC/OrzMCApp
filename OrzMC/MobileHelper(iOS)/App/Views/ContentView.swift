//
//  ContentView.swift
//  OrzMC
//
//  Created by joker on 2022/10/24.
//

import SwiftUI

/// iOS 的两个入口：
/// - **我的服务器**：自己用 `orzmc`（或 docker）起的服务端，SLP 看状态、RCON 发命令；
/// - **远程托管**：exaroton 账号下的服务器（与 macOS 的远程窗口同一套视图）。
///
/// 两者是并列关系而不是"主/次"：不注册任何第三方账号也能用第一个。
struct ContentView: View {
    var body: some View {
        TabView {
            NavigationStack {
                SelfHostedServerView()
            }
            .tabItem { Label("My Server", systemImage: "server.rack") }

            ExarotonContent()
                .tabItem { Label("Remote Hosting", systemImage: "cloud") }
        }
    }
}

#Preview {
    ContentView()
}
