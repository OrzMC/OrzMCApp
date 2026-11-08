//
//  ServersContentView.swift
//  OrzMC
//
//  **服务器管理页**（macOS「服务器」窗口 + iOS 唯一入口）：一个列表，按来源分组。
//
//  为什么合并（2026-11-08 维护者要求）：以前自建服务器与远程托管各是"一个面"，macOS 窗口用
//  顶部分段控件切换、iOS 用两个 Tab。用户的心智模型只有一句"我的服务器现在怎么样、我要对它做点什么"，
//  "服务器在哪"（自己的机器 / Exaroton / MCSManager 面板）是**同一张列表里的分组**，不是两个页面。
//  合并后：顶部不再有切换控件，页顶只有**一个**「添加服务器」菜单（先选类型，再填对应表单），
//  三种来源用同一套卡片（`ServerCard`）与同一套空/加载/失败态（`RemoteHostingSkeleton`）。
//
//  铁律：
//  · 分组顺序固定 **自建 → Exaroton → MCSManager**，不做筛选/分段控件；
//  · 一个来源一条记录都没有时**整组不渲染**（不是空卡片），整页一条都没有时给统一空态；
//  · 页顶只有一个添加入口（`AddServerMenu`），分组标题旁不再放按钮；
//  · 所有表单都由**这一层**弹 sheet（空态时分组还没渲染，挂在分组里会"点了没反应"）；
//  · 状态徽章 / 停止进度 / 控制台仍是各自唯一实现，这里只摆位置。
//

import OrzMCDesignSystem
import OrzMCLauncher
import OrzMCRemoteHosting
import SwiftUI

struct ServersContentView: View {
    @State private var selfHosted = SelfHostedServersModel()
    @State private var accounts = ExarotonAccountsModel()
    @State private var mcsm = MCSManagerPanelsModel()

    /// 当前要弹的表单。**用一个枚举 + `.sheet(item:)`**：
    /// 同一视图链上只能挂一个 `.sheet`，分开挂会互相吞掉（2026-11-05 实测）。
    @State private var editor: EditorSheet?
    /// 自建服务器详情路由：**value-based 导航**（不用 `NavigationLink` 包卡片）——
    /// 卡片上现在有刷新/配置/删除三个按钮，被链接包住时点击会被链接吞掉。
    @State private var path = NavigationPath()
    /// 全部折叠/展开（默认展开；与主窗口实例栏同一套规则：全局值 + 单组覆盖）。
    @AppStorage("orzmc.servers.allExpanded") private var allExpanded = true
    /// 单组覆盖：`分组 id → 是否展开`（点某一组标题时写入；切换全局模式时清空）。
    @State private var expansionOverrides: [String: Bool] = [:]
    /// 等待二次确认的删除目标（自建服务器：删档案 + Keychain 密码，服务器本身不动）。
    @State private var pendingDelete: SelfHostedServerProfile?
    @Environment(\.scenePhase) private var scenePhase

    /// 服务器从哪里来（添加菜单的第一层选择）。
    enum Source: String, CaseIterable, Identifiable {
        case selfHosted
        case exaroton
        case mcsmanager

        var id: String { rawValue }
    }

    enum EditorSheet: Identifiable {
        case selfHosted(SelfHostedServerProfile)
        /// `nil` = 新增账号。
        case exarotonAccount(ExarotonAccount?)
        case mcsmanagerPanel(MCSManagerPanelEditor.Mode)

        var id: String {
            switch self {
            case .selfHosted(let profile): return "selfHosted-\(profile.id)"
            case .exarotonAccount(let account): return "exaroton-\(account?.id.uuidString ?? "new")"
            case .mcsmanagerPanel(let mode): return "mcsm-\(mode.id)"
            }
        }
    }

    /// 自建 / Exaroton / MCSManager 一条记录都没有 → 只显示空态说明页。
    private var isEmpty: Bool {
        selfHosted.profiles.servers.isEmpty && accounts.accounts.isEmpty && mcsm.panels.isEmpty
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if isEmpty {
                    emptyPage
                } else {
                    listPage
                }
            }
            .navigationTitle(String(localized: "Servers"))
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .navigationDestination(for: SelfHostedServerRoute.self) { route in
                SelfHostedServerDetailView(profileID: route.id, model: selfHosted)
            }
        }
        .environment(accounts)
        .environment(mcsm)
        .task { accounts.setActive(scenePhase == .active) }
        .onChange(of: scenePhase) { _, phase in
            accounts.setActive(phase == .active)
            mcsm.isSceneActive = phase == .active
            // 回到前台时再与云端对一次（另一台设备的改动可能刚同步过来）。
            if phase == .active {
                accounts.syncWithCloud()
                mcsm.syncWithCloud()
            }
        }
        .sheet(item: $editor) { current in
            editor(for: current)
        }
        // 切「全部折叠 / 全部展开」= 重置单组覆盖，回到统一状态。
        .onChange(of: allExpanded) { expansionOverrides = [:] }
        .confirmationDialog(
            String(localized: "Delete This Server?"),
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { profile in
            Button(String(localized: "Delete"), role: .destructive) {
                selfHosted.remove(profile.id)
                pendingDelete = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { pendingDelete = nil }
        } message: { _ in
            Text(
                String(
                    localized: "Removes the address, the saved RCON password and the console history on this device. The server itself is not touched."
                )
            )
        }
        // 列表页定时探一遍自建服务器：卡片上的状态不该停在"上次打开列表时"的旧值。
        .task { await selfHosted.refreshAllStatuses() }
        .task(id: selfHosted.profiles.servers.count) {
            guard !selfHosted.profiles.servers.isEmpty else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                await selfHosted.refreshAllStatuses()
            }
        }
        #if os(iOS)
        .refreshable { await selfHosted.refreshAllStatuses() }
        #endif
        #if DEBUG
        .task { await Self.runDiagnosticsIfRequested(accounts: accounts) }
        #endif
    }
}

// MARK: - 页面

private extension ServersContentView {

    /// 页顶**唯一**的添加入口：先选服务器类型，再填该类型的表单。
    var addMenu: some View {
        AddServerMenu { source in
            switch source {
            case .selfHosted: editor = .selfHosted(SelfHostedServerProfile())
            case .exaroton: editor = .exarotonAccount(nil)
            case .mcsmanager: editor = .mcsmanagerPanel(.add)
            }
        }
    }

    /// 列表页的页顶一行：左「全部折叠 / 全部展开」，右「添加服务器」。
    ///
    /// 折叠控件与主窗口详情页的「实例栏」同一套观感（两个图标按钮 + `subtleFill` 底），
    /// 位置也贴着内容（列表上方），不是塞进窗口工具栏。
    var topBar: some View {
        HStack(spacing: OrzMCTheme.Spacing.sm) {
            sectionDisplayControls
            Spacer(minLength: 0)
            addMenu
        }
    }

    /// 分组展开状态：单组覆盖优先，否则跟随全局值。
    func sectionExpanded(_ id: String) -> Bool {
        expansionOverrides[id] ?? allExpanded
    }

    /// 注意：别把它命名成 `toggleSection(...)` —— 会撞上 `check-localization.py` 里
    /// `Section("…")` 的模式，把组 id 当界面文案去要翻译。
    private func toggleGroup(_ id: String) {
        expansionOverrides[id] = !sectionExpanded(id)
    }

    private func setAllExpanded(_ expanded: Bool) {
        allExpanded = expanded
        expansionOverrides = [:]
    }

    /// **全部折叠 / 全部展开**：两个动作按钮，点一下把所有分组设成同一状态。
    ///
    /// 不用 `Picker` 绑 `allExpanded`：单组折叠后全局值没变，再点"已选中的那一档"不会触发
    /// `onChange`，看起来就是按钮没用（主窗口 2026-10-22 实测踩过，这里沿用同一结论）。
    var sectionDisplayControls: some View {
        HStack(spacing: 2) {
            modeButton(
                systemImage: "rectangle.compress.vertical",
                label: "Collapse All",
                isActive: !allExpanded && expansionOverrides.isEmpty,
                identifier: "servers.collapseAll"
            ) {
                setAllExpanded(false)
            }
            modeButton(
                systemImage: "rectangle.expand.vertical",
                label: "Expand All",
                isActive: allExpanded && expansionOverrides.isEmpty,
                identifier: "servers.expandAll"
            ) {
                setAllExpanded(true)
            }
        }
        .padding(3)
        .background(OrzMCTheme.Palette.subtleFill, in: RoundedRectangle(cornerRadius: OrzMCTheme.Radius.md))
        .help("Collapse or expand every server group")
    }

    /// 单个模式按钮：图标态，选中档有底色；存在单组覆盖时两档都不高亮（= 混合状态）。
    private func modeButton(
        systemImage: String,
        label: LocalizedStringKey,
        isActive: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(label, systemImage: systemImage)
                .labelStyle(.iconOnly)
                .frame(width: 30, height: 22)
                .background {
                    if isActive {
                        RoundedRectangle(cornerRadius: OrzMCTheme.Radius.sm)
                            .fill(OrzMCTheme.Palette.selectionFill)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    /// 一条都没有：页顶入口 + 居中的空态说明。
    ///
    /// 入口用 `overlay` 浮在页顶：它**不占布局高度**，说明块才是相对**整页**居中
    /// （2026-11-06 维护者两次反馈"视觉上不居中"）。
    var emptyPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: OrzMCTheme.Spacing.xl)
            EmptyContentView(
                ContentState(
                    title: String(localized: "No servers yet"),
                    message: String(
                        localized: "Add a server you run yourself, or connect an Exaroton account / MCSManager panel — everything shows up in this list."
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

    /// 有内容：页顶入口 + 按来源分组（自建 → Exaroton → MCSManager；空的那组不出现）。
    var listPage: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.lg) {
                topBar
                if !selfHosted.profiles.servers.isEmpty {
                    SelfHostedServersSection(
                        model: selfHosted,
                        isExpanded: sectionExpanded("selfHosted"),
                        onToggle: { toggleGroup("selfHosted") },
                        onOpen: { path.append(SelfHostedServerRoute(id: $0.id)) },
                        onEdit: { editor = .selfHosted($0) },
                        onDelete: { pendingDelete = $0 }
                    )
                }
                if !accounts.accounts.isEmpty {
                    ExarotonAccountsSection(
                        onEditAccount: { editor = .exarotonAccount($0) },
                        isExpanded: sectionExpanded("exaroton"),
                        onToggle: { toggleGroup("exaroton") }
                    )
                }
                if !mcsm.panels.isEmpty {
                    MCSManagerSection(
                        onEditPanel: { editor = .mcsmanagerPanel(.edit($0)) },
                        isExpanded: sectionExpanded("mcsm"),
                        onToggle: { toggleGroup("mcsm") }
                    )
                }
            }
            .padding(OrzMCTheme.Spacing.lg)
            .containerRelativeFrame(.horizontal) { width, _ in min(width, 780) }
            .frame(maxWidth: .infinity)
        }
    }

    /// 按类型弹对应表单（三种来源共用同一个 sheet 入口）。
    @ViewBuilder
    func editor(for sheet: EditorSheet) -> some View {
        switch sheet {
        case .selfHosted(let profile):
            SelfHostedServerSettingsView(profile: profile) { updated, password, delete in
                if delete {
                    selfHosted.remove(updated.id)
                } else {
                    selfHosted.save(updated, rconPassword: password)
                    Task { await selfHosted.refreshAllStatuses() }
                }
                editor = nil
            }
        case .exarotonAccount(let account):
            ExarotonAccountEditorSheet(existing: account, onClose: { editor = nil })
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
                    editor = nil
                    Task { await mcsm.reloadAll(); mcsm.start() }
                    return true
                },
                onCancel: { editor = nil }
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
}

// MARK: - 添加入口

/// 页顶**唯一**的添加入口：一个菜单列出三种服务器来源。
///
/// 以前自建页是"直接弹表单"、远程页是"先选供应商"：两个面各有各的加法，用户要先知道
/// 自己在哪个面。现在统一成"先说是什么，再填表单"。
struct AddServerMenu: View {
    let onSelect: (ServersContentView.Source) -> Void

    var body: some View {
        Menu {
            item(
                .selfHosted,
                title: String(localized: "Self-hosted server"),
                systemImage: "server.rack"
            )
            Divider()
            // 供应商名是品牌名，不翻译（用 `verbatim`，避免进本地化表）。
            item(.exaroton, title: "Exaroton", systemImage: "cloud")
            item(.mcsmanager, title: "MCSManager", systemImage: "square.stack.3d.up")
        } label: {
            Label(String(localized: "Add Server"), systemImage: "plus.circle")
                .font(.callout)
        }
        .buttonStyle(.bordered)
        .accessibilityIdentifier("servers.addServer")
    }

    @ViewBuilder
    private func item(
        _ source: ServersContentView.Source,
        title: String,
        systemImage: String
    ) -> some View {
        Button {
            onSelect(source)
        } label: {
            Label {
                Text(verbatim: title)
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .accessibilityIdentifier("servers.add.\(source.rawValue)")
    }
}

// MARK: - 仅 DEBUG 的诊断

#if DEBUG
extension ServersContentView {
    /// **诊断钩子**（仅 DEBUG）：`ORZMC_DEMO_DIAGNOSE=1` 启动后自动连第一台 exaroton 服务器，
    /// 把 WS/ready/流/控制台状态写成 `Documents/orzmc-diagnose.json`。
    /// 用于真机排查"在线但控制台连不上"——真机不能点屏幕，但可以用 `devicectl device copy` 取回文件。
    @MainActor
    static func runDiagnosticsIfRequested(accounts: ExarotonAccountsModel) async {
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
                "status": describe(status: model.effectiveStatus(for: server)),
                "liveStatus": describe(status: model.servers.first.flatMap { model.effectiveStatus(for: $0) }),
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

    private static func describe(status: ServerStatus?) -> String {
        guard let status else { return "-" }
        return String(describing: status)
    }
}
#endif

/// 自建服务器详情的导航值（`Hashable` 路由，避免把整个档案塞进路径）。
struct SelfHostedServerRoute: Hashable {
    let id: UUID
}

#Preview {
    ServersContentView()
        .frame(width: 900, height: 620)
}
