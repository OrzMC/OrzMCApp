//
//  DirectoryRow.swift
//  OrzMC
//

import JokerKits
import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 一条目录：**标题 + 一句说明 + 右侧「打开」按钮**。
///
/// 不显示完整路径：路径前缀（`~/minecraft/versions/…`）人人相同、又长又占地方，
/// 用户真正要的是"这是干什么的" + 一键跳转。路径放在悬停提示里，需要时还能复制。
///
/// `exists` 由调用方在刷新任务里算好传进来——body 里不做文件 IO
/// （详情页会因定时刷新、任意状态变化反复求值）。
struct DirectoryRow: View {
    @Environment(AppModel.self) private var app

    let entry: GameDirectoryEntry
    let exists: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbolName)
                .foregroundStyle(exists ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                .frame(width: 18)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(LocalizedStringKey(entry.title))
                        .font(.body.weight(.medium))
                    if !exists {
                        OrzMCTag(String(localized: "not created yet"))
                    }
                }
                Text(LocalizedStringKey(entry.detail))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Button {
                open()
            } label: {
                Label("Open", systemImage: "arrow.up.forward.app")
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(exists ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .disabled(!exists)
            .help(exists ? "Open \(entry.path) in Finder" : "\(entry.path) does not exist yet")
        }
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { open() }
        .help(entry.path)
    }

    private var symbolName: String {
        switch entry.kind {
        case .root: return "folder"
        case .world: return "globe.asia.australia"
        case .logs: return "doc.text.magnifyingglass"
        case .plugins: return "puzzlepiece.extension"
        case .pluginUpdates: return "arrow.triangle.2.circlepath"
        case .mods: return "shippingbox"
        case .config: return "slider.horizontal.3"
        case .saves: return "bookmark"
        case .resourcePacks: return "paintpalette"
        }
    }

    /// 打开失败要说话：以前 `try?` 吞掉，用户只看到「没反应」。
    private func open() {
        guard exists else { return }
        do {
            try Shell.runCommand(with: ["open", entry.path])
        } catch {
            app.error = LauncherError(
                code: "E_IO",
                message: String(localized: "Could not open the folder. \(error.localizedDescription)")
            )
        }
    }
}
