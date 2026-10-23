//
//  ServersWindowContent.swift
//  OrzMC
//

import OrzMCDesignSystem
import SwiftUI

/// 「服务器」窗口：**自建服务器** 与 **exaroton 远程托管** 两个面。
///
/// 为什么放同一个窗口而不是两个窗口：两者回答的是同一个问题——"我的服务器现在怎么样、
/// 我要对它做点什么"，只是"服务器在哪"不同（自己的机器 / exaroton）。放一起后，
/// 窗口菜单里不会多出两个看不出区别的条目，也省了一套 ⌘W/Esc 行为。
struct ServersWindowContent: View {
    enum Mode: String, CaseIterable, Identifiable {
        case selfHosted
        case managed

        var id: String { rawValue }

        var title: String {
            switch self {
            case .selfHosted: return String(localized: "My Server")
            case .managed: return String(localized: "Remote Hosting")
            }
        }

        var systemImage: String {
            switch self {
            case .selfHosted: return "server.rack"
            case .managed: return "cloud"
            }
        }
    }

    /// 默认落在哪个面：已经配过自建地址就来自建，否则来自托管的账号页。
    @State private var mode: Mode = SelfHostedServerProfile.load().isConfigured ? .selfHosted : .managed

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $mode) {
                ForEach(Mode.allCases) { item in
                    Label(item.title, systemImage: item.systemImage).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, OrzMCTheme.Spacing.md)
            .padding(.vertical, OrzMCTheme.Spacing.sm)
            .accessibilityLabel(Text("Server type"))

            Divider()

            switch mode {
            case .selfHosted:
                NavigationStack { SelfHostedServerView() }
            case .managed:
                ExarotonContent()
            }
        }
        #if os(macOS)
        // Esc 关闭这个窗口（辅助窗口统一规则，见 `EscapeClosesWindow`）。
        .escapeClosesWindow()
        #endif
    }
}

#Preview {
    ServersWindowContent()
        .frame(width: 900, height: 620)
}
