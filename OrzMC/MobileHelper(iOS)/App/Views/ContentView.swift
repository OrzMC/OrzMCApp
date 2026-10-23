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
    /// 记住上次看的 Tab（重开 App / 重装 debug 包后不用每次点回远程托管）。
    @AppStorage("orzmc.ios.tab") private var storedTab = Tab.selfHosted.rawValue
    @State private var tab: Tab = Self.initialTab()

    enum Tab: String {
        case selfHosted
        case managed
    }

    var body: some View {
        TabView(selection: $tab) {
            NavigationStack {
                SelfHostedServerView()
            }
            .tabItem { Label("My Server", systemImage: "server.rack") }
            .tag(Tab.selfHosted)

            ExarotonContent()
                .tabItem { Label("Remote Hosting", systemImage: "cloud") }
                .tag(Tab.managed)
        }
        .onChange(of: tab) { storedTab = tab.rawValue }
    }

    /// 初始 Tab：优先用上次记忆；调试构建可用 `ORZMC_DEMO_TAB=managed|selfHosted` 强制定位
    /// （真机开屏验收/截图时用，免得每次都要手动点）。
    private static func initialTab() -> Tab {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["ORZMC_DEMO_TAB"], let forced = Tab(rawValue: raw) {
            return forced
        }
        #endif
        if let raw = UserDefaults.standard.string(forKey: "orzmc.ios.tab"), let stored = Tab(rawValue: raw) {
            return stored
        }
        return .selfHosted
    }
}

#Preview {
    ContentView()
}
