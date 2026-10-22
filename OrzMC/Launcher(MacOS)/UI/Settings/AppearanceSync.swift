//
//  AppearanceSync.swift
//  OrzMC
//

import AppKit
import SwiftUI

extension SettingsModel.Appearance {
    /// 落到 AppKit 的外观（`nil` = 跟随系统）。
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// 把「外观」设置同步到 `NSApp.appearance`。
///
/// 为什么不用 `.preferredColorScheme`：它只影响**一棵**视图树，而本应用有主窗口、控制台窗口、
/// 远程服务器窗口、设置窗口四类窗口（外加系统面板），逐个挂会漏；统一写 `NSApp` 才能一次覆盖。
struct AppearanceSync: ViewModifier {
    let appearance: SettingsModel.Appearance

    func body(content: Content) -> some View {
        content
            .onAppear { apply() }
            .onChange(of: appearance) { _, _ in apply() }
    }

    private func apply() {
        NSApp.appearance = appearance.nsAppearance
    }
}

extension View {
    /// 让视图所在的 App 跟随「外观」设置。
    func syncAppearance(_ appearance: SettingsModel.Appearance) -> some View {
        modifier(AppearanceSync(appearance: appearance))
    }
}
