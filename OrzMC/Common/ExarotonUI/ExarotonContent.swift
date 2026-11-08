//
//  ExarotonContent.swift
//  OrzMC
//
//  Created by joker on 2024/5/22.
//

import OrzMCDesignSystem
import OrzMCRemoteHosting
import SwiftUI

struct ExarotonContent: View {
    @State private var accounts = ExarotonAccountsModel()
    /// MCSManager 面板（P2-7 第 4 步）：与 exaroton **同一页按供应商分组**。
    @State private var mcsm = MCSManagerPanelsModel()
    /// 当前要弹的账号表单。
    ///
    /// ⚠️ 必须由**这一层**弹：空态页（一个账号都没有）时两家分组都还没渲染，
    /// 把 sheet 挂在分组里会出现"选了供应商什么也没发生"（2026-11-06 维护者实测）。
    @State private var editorSheet: EditorSheet?
    @Environment(\.scenePhase) private var scenePhase

    /// 两家供应商一个账号都没配 → 只显示空态说明页。
    private var isEmpty: Bool {
        accounts.accounts.isEmpty && mcsm.panels.isEmpty
    }

    enum EditorSheet: Identifiable {
        /// `nil` = 新增账号。
        case exarotonAccount(ExarotonAccount?)
        case mcsmanagerPanel(MCSManagerPanelEditor.Mode)

        var id: String {
            switch self {
            case .exarotonAccount(let account): return "exaroton-\(account?.id.uuidString ?? "new")"
            case .mcsmanagerPanel(let mode): return "mcsm-\(mode.id)"
            }
        }
    }

    #if DEBUG
    /// **诊断钩子**（仅 DEBUG）：`ORZMC_DEMO_DIAGNOSE=1` 启动后自动连第一台服务器，把 WS/ready/流/控制台
    /// 状态写成 `Documents/orzmc-diagnose.json`。用于真机排查"在线但控制台连不上"——
    /// 真机不能点屏幕，但可以用 `devicectl device copy` 把这个文件取回来。
    private func runDiagnosticsIfRequested() async {
        guard let mode = ProcessInfo.processInfo.environment["ORZMC_DEMO_DIAGNOSE"], mode != "0" else { return }
        guard let model = accounts.accounts.first.flatMap({ accounts.models[$0.id] }) else { return }
        await model.reloadList()
        guard let server = model.servers.first, let id = server.id else { return }
        // `ORZMC_DEMO_DIAGNOSE=start`：顺便把这台服务器启动起来，用来验证"在线 → 有流 → 控制台有日志"。
        var startResult = "-"
        if mode == "start" {
            let ok = await model.startServer(serverId: id)
            startResult = ok ? "ok" : "false · \(model.actionErrors[id] ?? model.actionMessages[id] ?? "-")"
        }
        model.startConnect(for: id)

        var report: [[String: String]] = []
        for step in 0..<12 {
            try? await Task.sleep(for: .seconds(5))
            report.append([
                "t": "\(step * 5)s",
                "isConnected": String(model.isConnected),
                "isLive": String(model.isLive),
                "readyServerID": model.readyServerID ?? "-",
                "expectedServerID": id,
                "activeStreams": model.activeStreams.map(\.rawValue).sorted().joined(separator: ","),
                "consoleLines": String(model.consoleLines.count),
                "disconnectedReason": model.disconnectedReason ?? "-",
                "errorMessage": model.errorMessage ?? "-",
                "status": Self.describe(model.effectiveStatus(for: server)),
                "liveStatus": Self.describe(model.servers.first.flatMap { model.effectiveStatus(for: $0) }),
                "startError": model.actionErrors[id] ?? "-",
                "startResult": startResult,
                "actionLog": ExarotonServerModel.debugActionLog.joined(separator: " | "),
            ])
        }
        let json = try? JSONSerialization.data(withJSONObject: report, options: .prettyPrinted)
        let url = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("orzmc-diagnose.json")
        try? json?.write(to: url)
    }

    private static func describe(_ status: ServerStatus?) -> String {
        guard let status else { return "-" }
        return String(describing: status)
    }
    #endif
    var body: some View {
        NavigationStack {
            // 空态是**整页居中**的说明页（不放进 ScrollView）：macOS 窗口又宽又高时，
            // 放在滚动视图顶部会贴着上半页，看着"没对齐"（2026-11-06 维护者截图）。
            // 有账号时才需要滚动（分组可能很多）。
            Group {
                if isEmpty {
                    emptyPage
                } else {
                    providerPage
                }
            }
            .navigationTitle(String(localized: "Remote Servers"))
        }
        .task { accounts.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            accounts.setActive(phase == .active)
            mcsm.isSceneActive = phase == .active
        }
        .sheet(item: $editorSheet) { current in
            editor(for: current)
        }
        #if DEBUG
        .task { await runDiagnosticsIfRequested() }
        #endif
    }
}

// MARK: - 页面

private extension ExarotonContent {

    /// 页顶唯一的添加入口（两家共用一个）。
    var addMenu: some View {
        HStack {
            Spacer(minLength: 0)
            RemoteAddProviderMenu { provider in
                switch provider {
                case .exaroton: editorSheet = .exarotonAccount(nil)
                case .mcsmanager: editorSheet = .mcsmanagerPanel(.add)
                }
            }
        }
    }

    /// 一个供应商都没配：页顶入口 + 居中的空态说明。
    ///
    /// 上下各放一个 `Spacer` 显式居中（不依赖 `ContentUnavailableView` 自己的布局）：
    /// macOS 窗口又宽又高、或被拖动改变大小时，说明块都要保持在**可视区正中**。
    var emptyPage: some View {
        // 添加入口用 `overlay` 浮在页顶：它**不占布局高度**，所以空态说明是相对**整页**居中，
        // 而不是被按钮挤到下半页（2026-11-06 维护者两次反馈"视觉上不居中"）。
        VStack(spacing: 0) {
            Spacer(minLength: OrzMCTheme.Spacing.xl)
            EmptyContentView(
                ContentState(
                    title: String(localized: "No remote servers"),
                    message: String(
                        localized: "Add an Exaroton account or an MCSManager panel (address + API Key) to see its servers here."
                    ),
                    systemImage: "server.rack"
                )
            )
            .frame(maxWidth: .infinity)
            Spacer(minLength: OrzMCTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            addMenu
                .padding(.horizontal, OrzMCTheme.Spacing.lg)
                .padding(.top, OrzMCTheme.Spacing.lg)
        }
        .containerRelativeFrame(.horizontal) { width, _ in min(width, 780) }
    }

    /// 按供应商弹对应表单（两家共用同一个 sheet 入口）。
    @ViewBuilder
    func editor(for sheet: EditorSheet) -> some View {
        switch sheet {
        case .exarotonAccount(let account):
            ExarotonAccountEditorSheet(existing: account, onClose: { editorSheet = nil })
                .environment(accounts)
        case .mcsmanagerPanel(let mode):
            MCSManagerPanelEditor(
                mode: mode,
                onSave: { label, url, key, storageMode in
                    switch mode {
                    case .add:
                        guard mcsm.addPanel(
                            label: label, rawURL: url, apiKey: key, storageMode: storageMode
                        ) else { return false }
                    case .edit(let panel):
                        guard mcsm.updatePanel(
                            id: panel.id, label: label, rawURL: url, apiKey: key, storageMode: storageMode
                        ) else { return false }
                    }
                    editorSheet = nil
                    Task { await mcsm.reloadAll(); mcsm.start() }
                    return true
                },
                onCancel: { editorSheet = nil }
            )
            .environment(mcsm)
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(OrzMCTheme.Radius.lg)
            .presentationCompactAdaptation(horizontal: .none, vertical: .sheet)
            #if os(iOS)
            .presentationDetents([.large])
            #endif
        }
    }

    /// 有账号：页顶入口 + 按供应商分组（顺序固定 exaroton → MCSManager，没配的那家整组不出现）。
    var providerPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.lg) {
                addMenu
                if !accounts.accounts.isEmpty {
                    ExarotonAccountsSection(onEditAccount: { editorSheet = .exarotonAccount($0) })
                        .environment(accounts)
                }
                if !mcsm.panels.isEmpty {
                    MCSManagerSection(onEditPanel: { editorSheet = .mcsmanagerPanel(.edit($0)) })
                        .environment(mcsm)
                }
            }
            .padding(OrzMCTheme.Spacing.lg)
            .containerRelativeFrame(.horizontal) { width, _ in min(width, 780) }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    ExarotonContent()
}
