//
//  MCSManagerSection.swift
//  OrzMC
//
//  P2-7 第 4 步（界面）：远程托管页里的 **MCSManager** 分组。
//
//  分组口径（维护者拍板）：多供应商**按供应商分组**，不做过滤 —— exaroton 保持自己的列表，
//  MCSManager 在同一个「远程托管」页里单独一组；每组各自显示实例与状态。
//
//  2026-11-05 跨端重构：分组的"标题行 / 账号卡 / 行骨架 / 加载·空·错误态"改走
//  `Common/RemoteHostingUI`（与 exaroton 同一套），这里只留 MCSM 特有的能力：
//  面板编辑、实例动作菜单、强杀二次确认、控制台 sheet，以及"点实例行 = 开控制台"。
//  状态徽章只有一个实现（`OrzMCStatusBadge`，经 `RemoteInstanceHeading`）。
//

import OrzMCDesignSystem
import OrzMCRemoteHosting
import SwiftUI

struct MCSManagerSection: View {

    @Environment(MCSManagerPanelsModel.self) private var mcsm

    /// 当前要显示的弹窗。
    ///
    /// ⚠️ **同一条视图链上只能挂一个 `.sheet`**：原来"编辑面板"和"控制台"各挂一个，
    /// 结果控制台那个永远不弹（真机/模拟器实测，UI 用例点「控制台」后界面毫无变化）。
    /// 合并成一个枚举就没这个问题。
    @State private var sheet: Sheet?

    /// 等待确认的「强制终止」目标（强杀会丢未保存进度，必须二次确认）。
    /// 用 `MCSManagerConsoleTarget` 只是为了顺手带上"它属于哪个面板的模型"。
    @State private var confirmingKill: MCSManagerConsoleTarget?

    enum Sheet: Identifiable {
        case editor(MCSManagerPanelEditor.Mode)
        case console(MCSManagerConsoleTarget)

        var id: String {
            switch self {
            case .editor(let mode): return "editor-\(mode.id)"
            case .console(let target): return "console-\(target.id)"
            }
        }
    }

    private var instanceCount: Int {
        mcsm.panels.reduce(0) { $0 + mcsm.instances(of: $1.id).count }
    }

    /// 一个面板都没配时给引导（与 exaroton 的空态同一套卡片）。
    private var emptyState: ContentState? {
        guard mcsm.panels.isEmpty else { return nil }
        return ContentState(
            title: String(localized: "No panels yet"),
            message: String(
                localized: "Add an MCSManager panel (address + API key) to see its instances here."
            ),
            systemImage: "square.stack.3d.up"
        )
    }

    var body: some View {
        RemoteProviderSection(
            name: "MCSManager",
            systemImage: "square.stack.3d.up",
            count: instanceCount,
            identifier: "mcsm.section",
            addIdentifier: "mcsm.addPanel",
            onAdd: { sheet = .editor(.add) },
            emptyState: emptyState
        ) {
            ForEach(mcsm.panels) { panel in
                panelCard(panel)
            }
        }
        .accessibilityElement(children: .contain)

        .sheet(item: $sheet) { current in
            switch current {
            case .editor(let mode):
                MCSManagerPanelEditor(
                    mode: mode,
                    onSave: { label, url, key in
                        switch mode {
                        case .add:
                            guard mcsm.addPanel(label: label, rawURL: url, apiKey: key) else { return false }
                        case .edit(let panel):
                            guard mcsm.updatePanel(id: panel.id, label: label, rawURL: url, apiKey: key) else {
                                return false
                            }
                        }
                        sheet = nil
                        Task { await mcsm.reloadAll(); mcsm.start() }
                        return true
                    },
                    onCancel: { sheet = nil }
                )
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(OrzMCTheme.Radius.lg)
                .presentationCompactAdaptation(horizontal: .none, vertical: .sheet)
                #if os(iOS)
                .presentationDetents([.large])
                #endif
            case .console(let target):
                MCSManagerConsoleSheet(instance: target.instance, model: target.model)
                    .presentationDragIndicator(.visible)
                    .presentationCompactAdaptation(horizontal: .none, vertical: .sheet)
                    #if os(iOS)
                    .presentationDetents([.large])
                    #endif
            }
        }
        .confirmationDialog(
            String(localized: "Force stop this server?"),
            isPresented: Binding(
                get: { confirmingKill != nil },
                set: { if !$0 { confirmingKill = nil } }
            ),
            titleVisibility: .visible,
            presenting: confirmingKill
        ) { target in
            Button(String(localized: "Force Stop"), role: .destructive) {
                Task { await target.model.perform(.kill, on: target.instance) }
                confirmingKill = nil
            }
            Button(String(localized: "Cancel"), role: .cancel) { confirmingKill = nil }
        } message: { target in
            Text(
                String(
                    localized: "“\(target.instance.nickname)” will be terminated immediately. Unsaved world data and player progress may be lost.",
                    comment: "强杀确认：说明会丢未保存数据"
                )
            )
        }
        .task {
            if mcsm.panels.isEmpty { return }
            await mcsm.reloadAll()
            mcsm.start()
        }
    }

    // MARK: - 组件

    /// 一个 MCSManager 面板 = 一张账号卡（与 exaroton 账号卡同一个骨架）。
    private func panelCard(_ panel: MCSManagerPanel) -> some View {
        let model = mcsm.model(for: panel.id)
        let instances = mcsm.instances(of: panel.id)

        return RemoteAccountCard(
            name: panel.label,
            subtitle: panel.url.host ?? panel.url.absoluteString,
            isLoading: model?.isLoading == true
        ) {
            RemoteAccountMenu(
                onRefresh: {
                    Task { await model?.reload() }
                },
                onEdit: {
                    sheet = .editor(.edit(panel))
                },
                onRemove: {
                    mcsm.removePanel(id: panel.id)
                },
                identifier: "mcsm.panelMenu"
            )
        } content: {
            // 失败要能就地重试：面板抽风（令牌过期 / 网络抖动）时不必杀进程重开。
            if let error = model?.errorMessage {
                RemoteInlineError(message: error) {
                    Task { await model?.reload() }
                }
            }
            if instances.isEmpty {
                if model?.isLoading == true {
                    RemoteInlineLoading()
                } else {
                    RemoteInlineEmpty()
                }
            } else {
                VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
                    ForEach(instances) { instance in
                        row(instance, model: model)
                    }
                }
            }
        }
    }

    /// 一条实例行：点名字/地址 = 打开控制台；生命周期动作留在 `⋯` 里（有副作用，多一步确认）。
    private func row(_ instance: MCSManagerInstance, model: MCSManagerModel?) -> some View {
        let state = model?.state(of: instance) ?? instance.status.remoteState

        return RemoteInstanceRow(
            name: instance.nickname,
            statusTitle: state.localizedTitle,
            statusStyle: state.statusStyle,
            onTap: {
                guard let model else { return }
                sheet = .console(MCSManagerConsoleTarget(instance: instance, model: model))
            },
            tapIdentifier: "mcsm.instanceRow",
            details: {
                if let address = instance.address {
                    Text(address)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            },
            trailing: {
                instanceAccessories(instance, model: model, state: state)
            },
            footer: {
                if let model, state == .stopping, let progress = model.stopProgress(for: instance) {
                    stopHint(instance, model: model, progress: progress)
                }
                if let error = model?.actionErrors[instance.id] {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(OrzMCTheme.Palette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        )
    }

    /// 右侧：玩家数 → 请求中转圈 → `⋯` 动作菜单（顺序固定，窄屏也不换位置）。
    @ViewBuilder
    private func instanceAccessories(
        _ instance: MCSManagerInstance,
        model: MCSManagerModel?,
        state: RemoteServerState
    ) -> some View {
        if let players = instance.players,
           let current = players.current, let max = players.max,
           state == .online {
            Text("\(current)/\(max)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        if model?.isBusy(instance) == true && state != .starting && state != .stopping && state != .restarting {
            ProgressView().controlSize(.mini)
        }
        if let model {
            actionsMenu(instance, model: model, state: state)
        }
    }

    /// 「正在停止…（12 秒）」——停止是异步的，用户需要知道它不是没反应；
    /// 等太久（`RemoteStopProgress.suggestsForceStop`）就顺手给出强杀入口。
    ///
    /// 每秒刷新一次是**必须**的（否则秒数不动，看着像卡死）：用 `TimelineView` 只重绘这一行的小字，
    /// 不去驱动整个列表。
    private func stopHint(
        _ instance: MCSManagerInstance,
        model: MCSManagerModel,
        progress: RemoteStopProgress
    ) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let live = model.stopProgress(for: instance, now: context.date) ?? progress
            HStack(spacing: 6) {
                if live.suggestsForceStop {
                    Text(
                        String(
                            localized: "Still stopping after \(live.seconds)s — it may be stuck.",
                            comment: "停止进度：久等提示，秒数为占位"
                        )
                    )
                    .foregroundStyle(OrzMCTheme.Palette.danger)
                    .accessibilityIdentifier("mcsm.stopProgress")
                } else {
                    Text(String(localized: "Stopping… \(live.seconds)s", comment: "停止进度秒数"))
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("mcsm.stopProgress")
                }
                if live.suggestsForceStop {
                    Button(String(localized: "Force Stop")) {
                        confirmingKill = MCSManagerConsoleTarget(instance: instance, model: model)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(OrzMCTheme.Palette.danger)
                    .accessibilityIdentifier("mcsm.forceStopInline")
                }
            }
            .font(.caption.monospacedDigit())
        }
    }

    /// 实例动作 + 控制台。动作按状态可用性置灰（过渡态一律不允许），
    /// 与 exaroton 走同一套判据（`RemoteServerListPolicy.canPerform`）。
    private func actionsMenu(
        _ instance: MCSManagerInstance,
        model: MCSManagerModel,
        state: RemoteServerState
    ) -> some View {
        Menu {
            ForEach([RemoteServerAction.start, .stop, .restart], id: \.self) { action in
                Button {
                    Task { await model.perform(action, on: instance) }
                } label: {
                    Label(action.localizedTitle, systemImage: action.systemImage)
                }
                .disabled(!model.canPerform(action, on: instance))
            }
            Divider()
            Button(role: .destructive) {
                confirmingKill = MCSManagerConsoleTarget(instance: instance, model: model)
            } label: {
                Label(RemoteServerAction.kill.localizedTitle, systemImage: RemoteServerAction.kill.systemImage)
            }
            .disabled(!model.canPerform(.kill, on: instance))
            .accessibilityIdentifier("mcsm.forceStop")
            Divider()
            Button {
                sheet = .console(MCSManagerConsoleTarget(instance: instance, model: model))
            } label: {
                Label(String(localized: "Console"), systemImage: "terminal")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("mcsm.instanceMenu")
        .accessibilityLabel(String(localized: "Server actions"))
    }
}

/// 控制台 sheet 的目标（实例 + 它所属面板的模型）。
///
/// `Identifiable` 要用实例 id：同一台实例打开两次是同一个目标，换实例才是新目标
/// （否则 sheet 会拿旧实例的状态去渲染）。
struct MCSManagerConsoleTarget: Identifiable {
    let instance: MCSManagerInstance
    let model: MCSManagerModel

    var id: String { "\(ObjectIdentifier(model)):\(instance.id)" }
}
