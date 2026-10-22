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
                .padding(.top, 14)
                .padding(.bottom, 10)

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
        .orzMCPanel()
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
                title: "Client",
                helpTitle: "\(instance.versionId) Client",
                statusText: statusText,
                statusStyle: statusStyle,
                isBusy: isBusy,
                consoleBtnAction: {
                    consoleTarget = ConsoleTarget(versionId: instance.versionId, software: nil)
                },
                consoleIsLive: consoleIsLive,
                deleteBtnAction: {
                    pendingRisky = .deleteClient(versionId: instance.versionId, path: rootPath)
                }
            )
        }
    }
}
