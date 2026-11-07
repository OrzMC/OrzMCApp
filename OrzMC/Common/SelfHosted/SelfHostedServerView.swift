//
//  SelfHostedServerView.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCLauncher
import OrzMCProtocol
import SwiftUI

/// 「我的服务器」**列表页**：页顶一个添加入口 + 服务器信息卡片列表，点卡片进详情页。
///
/// 结构对齐远程托管页（`ExarotonContent`）：同样"页顶唯一添加入口 + 卡片列表 + 点进详情"，
/// 这样窗口里两个面看起来是同一个 app。RCON / 玩家 / 控制台这些**与某台服务器强相关**的内容
/// 全部搬到详情页（`SelfHostedServerDetailView`）——以前它们平铺在列表下面，
/// 换服务器时整页内容重排，用户还得在一屏里找"哪块属于哪台"。
struct SelfHostedServerView: View {
    @State private var model = SelfHostedServersModel()
    /// 正在编辑的服务器档案。**用 `.sheet(item:)` 而不是 `isPresented + 可选值`**：
    /// 后者在"同一帧里既设值又置 true"时会用旧值（nil）构建内容，表现为 sheet 里一片空白
    /// （真机/模拟器都复现到过）。
    @State private var editing: SelfHostedServerProfile?

    private var servers: [SelfHostedServerProfile] { model.profiles.servers }

    var body: some View {
        Group {
            if servers.isEmpty {
                emptyPage
            } else {
                listPage
            }
        }
        .navigationTitle(String(localized: "My Server"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(item: $editing) { profile in
            SelfHostedServerSettingsView(profile: profile) { updated, password, delete in
                if delete {
                    model.remove(updated.id)
                } else {
                    model.save(updated, rconPassword: password)
                    Task { await model.refreshAllStatuses() }
                }
                editing = nil
            }
        }
        // 列表页也定时探一遍：回到列表时每张卡片的状态不该是"上次进详情前"的旧值。
        .task {
            await model.refreshAllStatuses()
        }
        .task(id: servers.count) {
            guard !servers.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await model.refreshAllStatuses()
            }
        }
        #if os(iOS)
        .refreshable { await model.refreshAllStatuses() }
        #endif
    }
}

// MARK: - 页面

private extension SelfHostedServerView {

    /// 页顶唯一的添加入口。
    ///
    /// 与远程托管页同一个位置、同一种样式（`plus.circle` + `.bordered`）：
    /// 两个面切换时按钮不会"跳"到别处。
    var addMenu: some View {
        HStack {
            Spacer(minLength: 0)
            Button {
                addServer()
            } label: {
                Label(String(localized: "Add Server"), systemImage: "plus.circle")
                    .font(.callout)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("selfHosted.addServer")
        }
    }

    /// 有服务器：页顶入口 + 卡片列表（每张卡整卡可点，进详情页）。
    var listPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.lg) {
                addMenu
                RemoteProviderSection(
                    name: String(localized: "Self-hosted"),
                    systemImage: "server.rack",
                    count: servers.count,
                    identifier: "selfHosted.section"
                ) {
                    ForEach(servers) { profile in
                        NavigationLink {
                            SelfHostedServerDetailView(profileID: profile.id, model: model)
                        } label: {
                            SelfHostedServerCard(
                                profile: profile,
                                status: model.status(for: profile.id),
                                statusError: model.statusErrorText(for: profile.id),
                                playersText: model.playersText(for: profile.id),
                                lastUpdated: model.lastUpdated(for: profile.id),
                                isProbing: model.isProbingAll
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("selfHosted.serverCard")
                    }
                }
            }
            .padding(OrzMCTheme.Spacing.lg)
            // iOS 26 的浮动 TabBar 会盖住滚动内容底部（SE 小屏实测过控制台输入行被压住）。
            .padding(.bottom, 76)
            .containerRelativeFrame(.horizontal) { width, _ in min(width, 780) }
            .frame(maxWidth: .infinity)
        }
    }

    /// 一台都没加：页顶入口浮在顶端 + 居中的说明页（与远程托管空态同一套 `EmptyContentView`）。
    var emptyPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: OrzMCTheme.Spacing.xl)
            EmptyContentView(
                ContentState(
                    title: String(localized: "No servers yet"),
                    message: String(
                        localized: "Add a Minecraft server you run yourself (address + port). The app checks it with Server List Ping; turn on RCON to run console commands."
                    ),
                    systemImage: "server.rack"
                )
            )
            .frame(maxWidth: .infinity)
            Spacer(minLength: OrzMCTheme.Spacing.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 入口用 `overlay` 浮在页顶：它**不占布局高度**，说明块才是相对整页居中
        // （与 `ExarotonContent.emptyPage` 同一个坑，2026-11-06 修过）。
        .overlay(alignment: .top) {
            addMenu
                .padding(.horizontal, OrzMCTheme.Spacing.lg)
                .padding(.top, OrzMCTheme.Spacing.lg)
        }
        .containerRelativeFrame(.horizontal) { width, _ in min(width, 780) }
    }

    func addServer() {
        editing = SelfHostedServerProfile()
    }
}

// MARK: - 卡片

/// 一台自建服务器的**信息卡片**。
///
/// 走统一的 `ServerCard`（自建 / exaroton / MCSManager 三处同一套排布与动作样式），
/// 字段顺序：`名称 + 状态徽标` → `地址` → `版本/玩家/延迟` 标签 → `MOTD` → 更新时间。
struct SelfHostedServerCard: View {
    let profile: SelfHostedServerProfile
    let status: MCStatusSummary?
    let statusError: String?
    let playersText: String?
    let lastUpdated: Date?
    /// 列表正在批量探测（还没拿到第一份结果时显示"检查中…"）。
    var isProbing = false

    private var statusTitle: String {
        if isProbing, status == nil { return String(localized: "Checking…") }
        return status != nil ? String(localized: "Online") : String(localized: "Offline")
    }

    private var statusStyle: OrzMCStatusStyle {
        if isProbing, status == nil { return .busy }
        return status != nil ? .running : .idle
    }

    private var tags: [String] {
        var tags: [String] = []
        if let version = status?.versionName { tags.append(version) }
        if let playersText { tags.append(playersText) }
        if let latency = status?.latencyMilliseconds, latency > 0 {
            tags.append(String(localized: "\(latency) ms"))
        }
        return tags
    }

    var body: some View {
        ServerCard(
            name: profile.displayName,
            statusTitle: statusTitle,
            statusStyle: statusStyle,
            address: profile.address,
            tags: tags,
            message: status?.motd,
            showsDisclosure: true
        ) {
            if let statusError {
                Text(verbatim: statusError)
                    .font(.caption)
                    .foregroundStyle(OrzMCTheme.Palette.danger)
                    .lineLimit(2)
            }
            // 这一行始终存在（没有更新时间就占位），否则首次加载完成后卡片会突然长高一行。
            Text(lastUpdated.map {
                String(localized: "Updated \($0.formatted(date: .omitted, time: .standard))")
            } ?? " ")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(height: 14, alignment: .leading)
        }
    }
}

#Preview {
    NavigationStack {
        SelfHostedServerView()
    }
}
