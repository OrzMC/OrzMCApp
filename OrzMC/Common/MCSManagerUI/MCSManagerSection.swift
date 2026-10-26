//
//  MCSManagerSection.swift
//  OrzMC
//
//  P2-7 第 4 步（界面）：远程托管页里的 **MCSManager** 分组。
//
//  分组口径（维护者拍板）：多供应商**按供应商分组**，不做过滤 —— exaroton 保持自己的列表，
//  MCSManager 在同一个「远程托管」页里单独一组；每组各自显示实例与状态。
//  状态徽章只有一个实现（`OrzMCStatusBadge`），这里只做布局。
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

    var body: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
            header

            if mcsm.panels.isEmpty {
                emptyCard
            } else {
                ForEach(mcsm.panels) { panel in
                    panelCard(panel)
                }
            }

            Button {
                sheet = .editor(.add)
            } label: {
                Label(String(localized: "Add Panel"), systemImage: "plus.circle")
                    .font(.callout)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.tint)
            .accessibilityIdentifier("mcsm.addPanel")
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mcsm.section")
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
        .task {
            if mcsm.panels.isEmpty { return }
            await mcsm.reloadAll()
            mcsm.start()
        }
    }

    // MARK: - 组件

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(String(localized: "MCSManager"))
                .font(.subheadline.weight(.semibold))
            if instanceCount > 0 {
                Text("\(instanceCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "No panels yet"))
                .font(.callout.weight(.medium))
            Text(String(localized: "Add an MCSManager panel (address + API key) to see its instances here."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OrzMCTheme.Spacing.md)
        .orzMCPanel()
    }

    private func panelCard(_ panel: MCSManagerPanel) -> some View {
        let model = mcsm.model(for: panel.id)
        let instances = mcsm.instances(of: panel.id)

        return VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            HStack(spacing: 6) {
                Text(panel.label)
                    .font(.callout.weight(.medium))
                Text(panel.url.host ?? panel.url.absoluteString)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if model?.isLoading == true {
                    ProgressView().controlSize(.mini)
                }
                Menu {
                    Button {
                        sheet = .editor(.edit(panel))
                    } label: {
                        Label(String(localized: "Edit Panel"), systemImage: "slider.horizontal.3")
                    }
                    Divider()
                    Button(role: .destructive) {
                        mcsm.removePanel(id: panel.id)
                    } label: {
                        Label(String(localized: "Remove Panel"), systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityIdentifier("mcsm.panelMenu")
            }

            if let error = model?.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(OrzMCTheme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if instances.isEmpty {
                Text(model?.isLoading == true ? String(localized: "Loading…") : String(localized: "No instances"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(instances) { instance in
                    row(instance, model: model)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OrzMCTheme.Spacing.md)
        .orzMCPanel()
    }

    private func row(_ instance: MCSManagerInstance, model: MCSManagerModel?) -> some View {
        let state = model?.state(of: instance) ?? instance.status.remoteState

        return VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                // 点实例名 = 打开控制台（最常用的动作给最直接的手势）。
                // 生命周期动作留在 `⋯` 菜单里 —— 那是"有副作用"的操作，要多一步确认。
                Button {
                    guard let model else { return }
                    sheet = .console(MCSManagerConsoleTarget(instance: instance, model: model))
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(instance.nickname)
                            .font(.callout)
                        if let address = instance.address {
                            Text(address)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model == nil)
                .accessibilityIdentifier("mcsm.instanceRow")
                Spacer(minLength: 8)
                if let players = instance.players,
                   let current = players.current, let max = players.max,
                   state == .online {
                    Text("\(current)/\(max)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                OrzMCStatusBadge(
                    verbatim: state.localizedTitle,
                    style: state.statusStyle
                )
                if model?.isBusy(instance) == true {
                    ProgressView().controlSize(.mini)
                }
                if let model {
                    actionsMenu(instance, model: model, state: state)
                }
            }

            if let error = model?.actionErrors[instance.id] {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(OrzMCTheme.Palette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
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
            Button {
                sheet = .console(MCSManagerConsoleTarget(instance: instance, model: model))
            } label: {
                Label(String(localized: "Console"), systemImage: "terminal")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
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

    var id: String { instance.id }
}
