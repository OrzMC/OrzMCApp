//
//  InstanceSection.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCLauncher
import SwiftUI

/// 详情页里的「一个实例」区块：目录清单 + 表头动作。
///
/// 为什么单独成视图：`Form` 的一个 Section 同时承载目录行与生命周期按钮，
/// 逻辑一多就变成 200 行的 `some View` 计算属性（views 规则要求抽成 `View` struct）。
///
/// 目录与「是否存在」由 `BasicInfo` 的刷新任务算好后传入，这里不做文件 IO。
struct InstanceSection: View {
    @Environment(AppModel.self) private var app

    let instance: DetailInstance
    let entries: [GameDirectoryEntry]
    /// `path → 是否存在`（由刷新任务填充）。
    let entryExists: [String: Bool]
    /// 该实例的根目录（删除时使用）。
    let rootPath: String
    let statusText: String
    let statusStyle: OrzMCStatusStyle
    /// 该实例的启动/下载进度（`nil` = 没在下载启动）。
    var progress: LaunchProgressState?
    /// 是否为工具栏"当前启动类型"对应的实例。
    var isCurrentType: Bool = false
    /// 是否展开（折叠时只保留表头那一行，页面可以一屏看完所有实例）。
    var isExpanded: Bool = true
    /// 折叠/展开这一栏（点标题或左侧箭头触发）。
    var toggleAction: () -> Void = {}
    let isBusy: Bool
    let consoleIsLive: Bool
    let availability: InstanceActionAvailability?

    @Binding var consoleTarget: ConsoleTarget?
    @Binding var pluginSheet: PluginSheetTarget?
    @Binding var pendingRisky: RiskyAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                // 展开时表头下面紧跟分隔线，底部留 10 就够；**折叠时整张卡片只有这一行**，
                // 上下必须对称（12/12），否则看起来"文字偏上/偏下"。
                .padding(.top, isExpanded ? 14 : 12)
                .padding(.bottom, isExpanded ? 10 : 12)

            if isExpanded {
                Divider()

                ForEach(Array(visibleEntries.enumerated()), id: \.element.id) { index, entry in
                let exists = entryExists[entry.path] ?? false
                DirectoryRow(entry: entry, exists: exists)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    // 只在行**之间**画分隔线：末尾那条会贴着面板底边，看起来像多了一道边。
                    if index < visibleEntries.count - 1 {
                        Divider().padding(.leading, 16)
                    }
                }
            }
        }
        .orzMCPanel()
        // 「当前启动类型」不用一个会挤动状态徽标的胶囊，而是把整张卡片描边高亮：
        // 几行状态徽标因此在同一条竖线上（切换类型时不会左右跳）。
        .overlay {
            if isCurrentType {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(OrzMCTheme.Palette.accent.opacity(0.55), lineWidth: 1.5)
                    .allowsHitTesting(false)
            }
        }
        .modifier(CurrentInstanceHint(isCurrent: isCurrentType))
    }

    /// 需要显示的行（未创建且「始终显示」的目录才出现）。
    private var visibleEntries: [GameDirectoryEntry] {
        entries.filter { entry in
            entry.showsWhenMissing || (entryExists[entry.path] ?? false)
        }
    }

    @ViewBuilder
    private var header: some View {
        if let software = instance.software {
            FormSectionHeader(
                title: "Server (\(software.rawValue))",
                helpTitle: "\(instance.versionId) \(software.rawValue)",
                statusText: statusText,
                statusStyle: statusStyle,
                isBusy: isBusy,
                progress: progress,
                availability: availability,
                consoleBtnAction: {
                    consoleTarget = ConsoleTarget(versionId: instance.versionId, software: software)
                },
                consoleIsLive: consoleIsLive,
                pluginsBtnAction: software.supportsPlugins ? {
                    pluginSheet = PluginSheetTarget(versionId: instance.versionId)
                } : nil,
                startBtnAction: {
                    app.control(.start, versionId: instance.versionId, software: software)
                },
                restartBtnAction: {
                    pendingRisky = .restartServer(versionId: instance.versionId, software: software)
                },
                stopBtnAction: {
                    pendingRisky = .stopServer(versionId: instance.versionId, software: software)
                },
                terminateBtnAction: {
                    pendingRisky = .terminateServer(versionId: instance.versionId, software: software)
                },
                isExpanded: isExpanded,
                toggleAction: toggleAction,
                deleteBtnAction: {
                    pendingRisky = .deleteServer(
                        versionId: instance.versionId,
                        software: software,
                        path: rootPath
                    )
                }
            )
        } else {
            FormSectionHeader(
                title: "Client (\(instance.clientKind?.rawValue ?? ""))",
                helpTitle: "\(instance.versionId) Client",
                statusText: statusText,
                statusStyle: statusStyle,
                isBusy: isBusy,
                progress: progress,
                consoleBtnAction: {
                    consoleTarget = ConsoleTarget(versionId: instance.versionId, software: nil)
                },
                consoleIsLive: consoleIsLive,
                isExpanded: isExpanded,
                toggleAction: toggleAction,
                deleteBtnAction: {
                    pendingRisky = .deleteClient(versionId: instance.versionId, path: rootPath)
                }
            )
        }
    }
}

/// 「当前启动类型」的说明：只在当前那一张卡片上挂 tooltip（`.help("")` 会留下空气泡）。
private struct CurrentInstanceHint: ViewModifier {
    let isCurrent: Bool

    func body(content: Content) -> some View {
        if isCurrent {
            content.help("Start button launches this instance")
        } else {
            content
        }
    }
}
