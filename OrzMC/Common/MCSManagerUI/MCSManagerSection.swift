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

    @State private var isAddingPanel = false

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
                isAddingPanel = true
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
        .sheet(isPresented: $isAddingPanel) {
            MCSManagerPanelEditor(
                onSave: { label, url, key in
                    guard mcsm.addPanel(label: label, rawURL: url, apiKey: key) else { return false }
                    isAddingPanel = false
                    Task { await mcsm.reloadAll() ; mcsm.start() }
                    return true
                },
                onCancel: { isAddingPanel = false }
            )
            .presentationDragIndicator(.visible)
            .presentationDetents([.height(360)])
            .presentationCornerRadius(OrzMCTheme.Radius.lg)
            .presentationCompactAdaptation(horizontal: .none, vertical: .sheet)
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
                    row(instance)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(OrzMCTheme.Spacing.md)
        .orzMCPanel()
    }

    private func row(_ instance: MCSManagerInstance) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(instance.nickname)
                    .font(.callout)
                if let address = instance.address {
                    Text(address)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let players = instance.players,
               let current = players.current, let max = players.max,
               instance.status == .running {
                Text("\(current)/\(max)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            OrzMCStatusBadge(
                verbatim: instance.status.remoteState.localizedTitle,
                style: instance.status.remoteState.statusStyle
            )

        }
    }
}

/// 添加面板：地址 + API Key（+ 可选显示名）。
struct MCSManagerPanelEditor: View {

    let onSave: (_ label: String, _ url: String, _ apiKey: String) -> Bool
    let onCancel: () -> Void

    @Environment(MCSManagerPanelsModel.self) private var mcsm

    @State private var label = ""
    @State private var url = ""
    @State private var apiKey = ""

    private var canSave: Bool {
        !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(String(localized: "Panel name (optional)"), text: $label)
                        .accessibilityIdentifier("mcsm.labelField")
                    TextField(String(localized: "Panel address, e.g. panel.example.com"), text: $url)
                        .textContentType(.URL)
                        #if os(iOS)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("mcsm.urlField")
                    SecureField(String(localized: "API Key"), text: $apiKey)
                        .accessibilityIdentifier("mcsm.apiKeyField")
                } footer: {
                    Text(
                        String(
                            localized: "Create the key in the panel under your user profile. API Key access must be enabled in the panel settings."
                        )
                    )
                    .font(.caption)
                }

                if let error = mcsm.lastValidationError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(OrzMCTheme.Palette.danger)
                    }
                }
            }
            .navigationTitle(String(localized: "Add Panel"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(String(localized: "Cancel")) { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(String(localized: "Save")) {
                        _ = onSave(label, url, apiKey)
                    }
                    .disabled(!canSave)
                    .accessibilityIdentifier("mcsm.savePanel")
                }
            }
        }
    }
}
