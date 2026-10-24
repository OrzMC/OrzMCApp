//
//  ExarotonServerList.swift
//  OrzMC
//
//  Created by joker on 2024/5/17.
//

import OrzMCDesignSystem
import SwiftUI

/// Exaroton 远程服务器列表（macOS / iOS 共用）。
///
/// 交互统一：
/// - 行用 `NavigationLink(value:)`（而不是 `onTapGesture`）：有系统高亮、键盘导航、
///   辅助功能“按钮”语义和返回手势；
/// - 空状态用 `ContentUnavailableView`，并直接给出“添加 Token”的动作；
/// - 加载用条件渲染的 `ProgressView`，不再用 `.opacity(0)`（透明但仍然拦截点击）。
struct ExarotonServerList: View {
    @Environment(ExarotonServerModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase

    @State private var token: String = ""
    @State private var showTokenInput = false

    private var isEmpty: Bool {
        model.servers.isEmpty && model.creditPools.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
                summaryCard

                if let message = model.listLoadError, !isEmpty {
                    errorCard(message)
                }

                if model.isLoadingList, isEmpty {
                    loadingCard
                } else if isEmpty {
                    emptyCard
                } else {
                    if !model.servers.isEmpty {
                        sectionHeader(
                            String(localized: "Servers"),
                            systemImage: "server.rack",
                            count: model.servers.count
                        )
                        ForEach(model.servers, id: \.id) { server in
                            // 整卡是一个按钮（Tab 能选中、VoiceOver 念成按钮）。
                            // 卡内不再放可点元素（"复制地址"只在详情页出现），避免嵌套按钮互相吞点击。
                            Button {
                                model.path.append(server)
                            } label: {
                                ExarotonServerCard(
                                    server: server,
                                    status: model.effectiveStatus(for: server),
                                    showsCopy: false
                                )
                                    .padding(OrzMCTheme.Spacing.md)
                                    .orzMCPanel()
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .orzMCPointerHover()
                            // UI 测试要能区分"服务器卡"与"额度池卡"（两者标题都可能带 PaperMC）。
                            .accessibilityIdentifier("remote.serverCard")
                        }
                    }
                    if !model.creditPools.isEmpty {
                        sectionHeader(
                            String(localized: "Credit Pools"),
                            systemImage: "bubbles.and.sparkles",
                            count: model.creditPools.count
                        )
                        ForEach(model.creditPools) { creditPool in
                            Button {
                                model.path.append(creditPool)
                            } label: {
                                ExarotonCreditPoolView(creditPool: creditPool)
                                    .padding(OrzMCTheme.Spacing.md)
                                    .orzMCPanel()
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .orzMCPointerHover()
                        }
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(String(localized: "Remote Servers"))
#if os(iOS)
        // macOS 的 List 没有下拉刷新，`.refreshable` 在这里只是个不会执行的装饰；工具栏已有刷新。
        .refreshable {
            await model.reloadList()
        }
#endif
        .sheet(isPresented: $showTokenInput) {
            ExarotonAccountTokenInputView(
                token: $token,
                onSave: saveToken,
                onCancel: { showTokenInput = false }
            )
            .presentationDragIndicator(.visible)
            .presentationDetents([.height(320)])
            .presentationCornerRadius(OrzMCTheme.Radius.lg)
            .presentationCompactAdaptation(horizontal: .none, vertical: .sheet)
            .interactiveDismissDisabled(model.isLoadingList)
        }
        .task {
            token = model.token
            if !model.token.isEmpty {
                await model.reloadList()
            }
        }
        // 低频轮询：WebSocket 是**按服务器**连的，只有进详情才会连；
        // 用户停在列表页时如果不轮询，状态就永远停在打开那一刻（真机反馈"状态不准确"）。
        // 已经有 WebSocket 时（详情页开着）就不必再拉 HTTP。
        .task {
            guard !model.token.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                if Task.isCancelled { break }
                if !model.isLive { await model.reloadList() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // 回到前台立刻刷新一次：后台期间状态可能已经变了。
            if phase == .active, !model.token.isEmpty {
                Task { await model.reloadList() }
            }
        }
        .task {
            #if DEBUG
            // 调试构建：`ORZMC_DEMO_FAKE_SERVER=1` 注入一台假服务器（不需要 exaroton Token），
            // 用来在没有账号/钥匙串的环境（CI、模拟器、无签名桌面包）里验收详情页布局。
            if ProcessInfo.processInfo.environment["ORZMC_DEMO_FAKE_SERVER"] == "1", model.servers.isEmpty {
                model.servers = [Self.demoServer]
            }
            // `--remote-detail` 直接进第一台服务器的详情页，便于快照这个次级窗口。
            if ProcessInfo.processInfo.arguments.contains("--remote-detail"),
               let first = model.servers.first {
                model.path.append(first)
            }
            #endif
        }
        .navigationDestination(for: ExarotonServer.self) { server in
            ExarotonServerDetail(server: server).environment(model)
        }
        .navigationDestination(for: ExarotonCreditPool.self) { creditPool in
            ExarotonCreditPoolDetail(creditPool: creditPool).environment(model)
        }
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

    // MARK: - 页面部件

    /// 顶部摘要卡：这一页在管什么 + 现在连上没有 + 刷新。
    /// 与主窗口的"启动卡"同一套外观语言（面板底 + accent 薄渐变），
    /// 让这个窗口看起来是同一个 app 的另一个面，而不是另一个工具。
    private var summaryCard: some View {
        // 窄屏（iPhone SE ~375pt）时"图标 + 说明 + 两个按钮"挤在一行会把说明压成每行几个字，
        // 卡片变得又高又难读。`ViewThatFits` 优先用一行布局，放不下就自动换成"按钮另起一行"。
        ViewThatFits(in: .horizontal) {
            summaryLayout(vertical: false)
            summaryLayout(vertical: true)
        }
        .padding(OrzMCTheme.Spacing.md)
        .background {
            let shape = RoundedRectangle(cornerRadius: OrzMCTheme.Radius.lg, style: .continuous)
            shape
                .fill(OrzMCTheme.Palette.panelFill)
                .overlay {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                OrzMCTheme.Palette.accent.opacity(0.10),
                                OrzMCTheme.Palette.accent.opacity(0.0),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                }
                .overlay {
                    shape.strokeBorder(OrzMCTheme.Palette.accent.opacity(0.22), lineWidth: 1)
                }
        }
    }

    @ViewBuilder
    private func summaryLayout(vertical: Bool) -> some View {
        let header = HStack(alignment: .center, spacing: OrzMCTheme.Spacing.md) {
            Image(systemName: "server.rack")
                .font(.title2)
                .foregroundStyle(OrzMCTheme.Palette.accent)
                .frame(width: 32)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text("Remote Hosting")
                    .font(.headline)
                Text("Actions run on exaroton's side; Stop and Restart disconnect connected players.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }

        let actions = HStack(spacing: OrzMCTheme.Spacing.sm) {
            // 加载指示器常驻占位，避免刷新时卡片高度跳动。
            ProgressView()
                .controlSize(.small)
                .opacity(model.isLoadingList ? 1 : 0)
                .frame(width: 16, height: 16)
                .accessibilityLabel(Text("Loading remote servers…"))

            Button {
                Task { await model.reloadList() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isLoadingList)
            .help("Reload remote servers")
            #if os(macOS)
            .keyboardShortcut("r", modifiers: .command)
            #endif

            Button {
                token = model.token
                showTokenInput = true
            } label: {
                Label("Account", systemImage: "key")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(model.isLoadingList || model.gate.isBusy)
            .help("Change exaroton account token")
        }

        if vertical {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
                header
                actions
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .center, spacing: OrzMCTheme.Spacing.md) {
                header
                Spacer(minLength: OrzMCTheme.Spacing.sm)
                actions
            }
        }
    }

    private func sectionHeader(_ title: String, systemImage: String, count: Int) -> some View {
        HStack(spacing: OrzMCTheme.Spacing.xs) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
            Text("\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.top, OrzMCTheme.Spacing.xs)
    }

    private var loadingCard: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            ProgressView().controlSize(.small)
            Text("Loading remote servers…")
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(OrzMCTheme.Spacing.md)
        .orzMCPanel()
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            OrzMCBanner(verbatim: message, role: .error)
            Button("Retry") { Task { await model.reloadList() } }
                .disabled(model.isLoadingList)
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            Label("No remote servers", systemImage: "server.rack")
                .font(.headline)

            if model.token.isEmpty {
                Text("Sign in with your exaroton account token to manage remote servers here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add Account Token…") { showTokenInput = true }
                    .buttonStyle(.borderedProminent)
            } else if let message = model.listLoadError {
                Text(verbatim: message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Retry") { Task { await model.reloadList() } }
            } else if model.hasLoadedList {
                Text("This account has no servers or credit pools.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OrzMCTheme.Spacing.lg)
        .orzMCPanel()
    }

    // MARK: - 动作

    private func saveToken() {
        let validToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !validToken.isEmpty else { return }
        guard !model.isLoadingList else { return }
        if validToken != model.token {
            model.servers = []
            model.creditPools = []
            model.hasLoadedList = false
            model.actionMessages = [:]
            model.actionErrors = [:]
            model.savedMemory = [:]
            model.memoryRevision = [:]
            model.memoryErrors = [:]
            model.memoryLoadErrors = [:]
            model.gate.reset()
            model.path = NavigationPath()
        }
        model.token = validToken
        showTokenInput = false
        Task { await model.reloadList() }
    }
}

#Preview {
    ExarotonServerList()
        .environment(ExarotonServerModel())
}
