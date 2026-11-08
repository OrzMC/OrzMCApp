import OrzMCDesignSystem
import SwiftUI

/// One account's instances and credit pools. Credentials and page composition belong to the account owner.
struct ExarotonServerList: View {
    @Environment(ExarotonServerModel.self) private var model
    @State private var showsDemoDetail = false

    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
            // 加载 / 空 / 失败三态与 MCSM 分组共用一套排版（`RemoteHostingSkeleton.swift`）：
            // 同一个窗口里两段必须"长得一样、都在说话"。
            if let message = model.listLoadError {
                RemoteInlineError(message: message) {
                    Task { await model.reloadList() }
                }
            }
            if model.isLoadingList && model.servers.isEmpty {
                RemoteInlineLoading()
            } else if model.servers.isEmpty && model.creditPools.isEmpty && model.listLoadError == nil {
                RemoteInlineEmpty()
            }
            // 行现在是**平铺**的（`.plain`，由账号卡提供唯一表面）：行与行之间用一条细线分隔，
            // 和系统分组列表一致；不再每行套一层玻璃面板。
            ForEach(Array(model.servers.enumerated()), id: \.offset) { index, server in
                if index > 0 { RemoteRowDivider() }
                ExarotonServerCardLink(server: server)
            }
            if !model.creditPools.isEmpty {
                RemoteSubsectionLabel(title: String(localized: "Credit Pools"), systemImage: "bubbles.and.sparkles")
                ForEach(Array(model.creditPools.enumerated()), id: \.offset) { index, pool in
                    if index > 0 { RemoteRowDivider() }
                    NavigationLink {
                        ExarotonCreditPoolDetail(creditPool: pool).environment(model)
                    } label: {
                        ExarotonCreditPoolView(creditPool: pool)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("remote.creditPoolCard")
                }
            }
        }
        .task {
            model.startBackgroundRefresh()
            if !model.token.isEmpty { await model.reloadList() }
        }
        .task {
            #if DEBUG
            // 调试构建：`ORZMC_DEMO_FAKE_SERVER=1` 注入一台假服务器（不需要 exaroton Token），
            // 用来在没有账号/钥匙串的环境（CI、模拟器、无签名桌面包）里验收详情页布局。
            if ProcessInfo.processInfo.environment["ORZMC_DEMO_FAKE_SERVER"] == "1", model.servers.isEmpty {
                model.servers = [Self.demoServer]
                if ProcessInfo.processInfo.environment["ORZMC_DEMO_FAKE_POOL"] == "1" {
                    model.creditPools = [.init(id: "demo-pool", name: "Demo Pool", credits: 10, servers: 1)]
                }
                // `ORZMC_DEMO_FAKE_STATUS=starting|online|offline`：把假服务器钉在某个状态，
                // 用来验收"徽章图标是否在转 / 状态文案"（默认离线，不会转）。
                if let raw = ProcessInfo.processInfo.environment["ORZMC_DEMO_FAKE_STATUS"],
                   let id = Self.demoServer.id {
                    let mapping: [String: ServerStatus] = [
                        "starting": .STARTING, "online": .ONLINE, "offline": .OFFLINE,
                        "stopping": .STOPPING, "transferring": .TRANSFERRING, "unknown": .UNKNOWN,
                    ]
                    if let status = mapping[raw.lowercased()] {
                        model.liveStatuses[id] = status
                    }
                }
            }
            // `--remote-detail` 直接进第一台服务器的详情页，便于快照这个次级窗口。
            if ProcessInfo.processInfo.arguments.contains("--remote-detail"),
               model.servers.first != nil {
                showsDemoDetail = true
            }
            #endif
        }
        .navigationDestination(isPresented: $showsDemoDetail) {
            if let first = model.servers.first { ExarotonServerDetail(server: first).environment(model) }
        }
        .alert("Remote Server Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: { Text(verbatim: model.errorMessage ?? "") }
    }
}

extension ExarotonServerList {
    #if DEBUG
    /// 仅用于界面验收的假服务器（数据形状与真实响应一致）。
    static var demoServer: ExarotonServer {
        .init(
            id: "ATMiLQGZ43vW2k3W",
            name: "jokerhub",
            address: nil,
            motd: "§b欢迎来到 jokerhub 的海外服务器！",
            status: .init(rawValue: ServerStatus.OFFLINE.rawValue),
            host: "jokerhub.exaroton.me",
            port: 39742,
            players: .init(max: 20, count: 0, list: []),
            software: .init(id: "1", name: "PaperMC", version: "26.3 (218)"),
            shared: false
        )
    }
    #endif

}
