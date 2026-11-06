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
    /// 页顶添加入口选中的供应商：对应分组的编辑器据此弹表单（选完即清）。
    @State private var addRequest: ProviderKind?
    @Environment(\.scenePhase) private var scenePhase

    /// 两家供应商一个账号都没配 → 只显示空态说明页。
    private var isEmpty: Bool {
        accounts.accounts.isEmpty && mcsm.panels.isEmpty
    }

    private var pageEmptyState: some View {
        EmptyContentView(
            ContentState(
                title: String(localized: "No remote servers"),
                message: String(
                    localized: "Add an exaroton account or an MCSManager panel (address + API Key) to see its servers here."
                ),
                systemImage: "server.rack"
            )
        )
        .frame(maxWidth: .infinity)
        .padding(.top, OrzMCTheme.Spacing.xl)
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
            ScrollView {
                // 分组顺序 = `ProviderKind.allCases`：**exaroton → MCSManager**，固定不变。
                // 这是维护者拍板的产品口径（按供应商分组、不做筛选器、不调顺序），
                // 新增供应商时把新分组接在后面，别插到前面去。
                //
                // 一个供应商都没配时不渲染任何分组：只给一个空态说明页 + 页顶唯一的添加入口
                // （以前是两个空卡片，用户会以为其中一个是坏的）。
                VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.lg) {
                    HStack {
                        Spacer(minLength: 0)
                        RemoteAddProviderMenu { provider in
                            addRequest = provider
                        }
                    }

                    if isEmpty {
                        pageEmptyState
                    } else {
                        // 只有配置了账号的供应商才出现（对应版块与服务器）。
                        if !accounts.accounts.isEmpty {
                            ExarotonAccountsSection(addRequest: $addRequest)
                                .environment(accounts)
                        }
                        if !mcsm.panels.isEmpty {
                            MCSManagerSection(addRequest: $addRequest)
                                .environment(mcsm)
                        }
                    }
                }
                .padding(OrzMCTheme.Spacing.lg)
                .containerRelativeFrame(.horizontal) { width, _ in min(width, 780) }
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(String(localized: "Remote Servers"))
        }
        .task { accounts.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            accounts.setActive(phase == .active)
            mcsm.isSceneActive = phase == .active
        }
        #if DEBUG
        .task { await runDiagnosticsIfRequested() }
        #endif
    }
}

#Preview {
    ExarotonContent()
}
