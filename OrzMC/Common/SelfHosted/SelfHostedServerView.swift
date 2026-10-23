//
//  SelfHostedServerView.swift
//  OrzMC
//

import OrzMCDesignSystem
import OrzMCProtocol
import SwiftUI

/// 「自建服务器」页：**看状态 + 发控制台命令**。
///
/// 与远程托管（exaroton）是两条并列的路：
/// - exaroton：账号 + 官方 API + WebSocket；
/// - 自建：直接 Server List Ping 查状态、RCON 发命令，不需要任何第三方账号。
///
/// 同一份代码 macOS / iOS 都能用（只用跨平台 API），目前先在 iOS 上露出。
struct SelfHostedServerView: View {
    @State private var model = SelfHostedServerModel()
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
                if model.profile.isConfigured {
                    statusCard
                    if let statusError = model.statusError { errorCard(statusError) }
                    if let names = model.status?.sampleNames, !names.isEmpty { playersCard(names) }
                    if model.profile.rconEnabled { consoleCard }
                } else {
                    setupCard
                }
            }
            .padding(20)
            .frame(maxWidth: 780)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(String(localized: "My Server"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.refreshStatus() }
        #endif
        .toolbar {
            ToolbarItemGroup {
                Button {
                    Task { await model.refreshStatus() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(!model.profile.isConfigured || model.isProbing)
                .help("Check the server status now")

                Button {
                    showSettings = true
                } label: {
                    Label("Settings", systemImage: "slider.horizontal.3")
                }
                .help("Server address, port and RCON")
            }
        }
        .sheet(isPresented: $showSettings) {
            SelfHostedServerSettingsView(profile: model.profile) { updated in
                model.profile = updated
                Task { await model.refreshStatus() }
            }
        }
        // 页面可见时每 20s 刷一次状态（比手动点的默认节奏慢得多，够用且省电）。
        .task(id: model.profile) {
            guard model.profile.isConfigured else { return }
            while !Task.isCancelled {
                await model.refreshStatus()
                try? await Task.sleep(for: .seconds(20))
            }
        }
    }

    // MARK: - 状态卡

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: OrzMCTheme.Spacing.sm) {
                Text(displayName)
                    .font(.headline)
                    .lineLimit(1)
                OrzMCStatusBadge(verbatim: statusText, style: statusStyle)
                Spacer(minLength: 0)
                if model.isProbing {
                    ProgressView().controlSize(.small)
                }
            }

            Text(model.profile.address)
                .font(OrzMCTheme.Typography.code)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: OrzMCTheme.Spacing.xs) {
                if let version = model.status?.versionName {
                    OrzMCTag(version)
                }
                if let players = model.playersText {
                    OrzMCTag(players)
                }
                if let latency = model.status?.latencyMilliseconds, latency > 0 {
                    OrzMCTag(String(localized: "\(latency) ms"))
                }
                Spacer(minLength: 0)
            }

            if let motd = model.status?.motd, !motd.isEmpty {
                Text(verbatim: motd)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let updated = model.lastUpdatedAt {
                Text("Updated \(updated.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(OrzMCTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
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

    private var displayName: String {
        let name = model.profile.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? model.profile.host : name
    }

    private var statusText: String {
        if model.isProbing, model.status == nil { return String(localized: "Checking…") }
        guard model.status != nil else { return String(localized: "Offline") }
        return String(localized: "Online")
    }

    private var statusStyle: OrzMCStatusStyle {
        if model.isProbing, model.status == nil { return .busy }
        return model.status != nil ? .running : .idle
    }

    private func errorCard(_ message: String) -> some View {
        OrzMCBanner(verbatim: message, role: .warning)
    }

    // MARK: - 玩家

    private func playersCard(_ names: [String]) -> some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.xs) {
            Label("Players online (\(names.count))", systemImage: "person.2")
                .font(.subheadline.weight(.semibold))
            ForEach(names, id: \.self) { name in
                Text(verbatim: name)
                    .font(OrzMCTheme.Typography.code)
            }
        }
        .padding(OrzMCTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orzMCPanel()
    }

    // MARK: - 控制台

    private var consoleCard: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            HStack {
                Label("Console (RCON)", systemImage: "terminal")
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                Button("Clear") { model.clearConsole() }
                    .font(.caption)
                    .disabled(model.consoleLines.isEmpty)
            }

            consoleLog

            HStack(spacing: OrzMCTheme.Spacing.sm) {
                TextField("", text: $model.commandDraft, prompt: Text("Say something or run a command"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .submitLabel(.send)
                    #endif
                    .onSubmit { send() }

                Button("Send") { send() }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isSending || model.commandDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if !model.canRunCommands {
                Text("RCON needs a password. Add it in Settings to send commands.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(OrzMCTheme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orzMCPanel()
    }

    private var consoleLog: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    if model.consoleLines.isEmpty {
                        Text("Commands and replies show up here.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(model.consoleLines) { line in
                        Text(verbatim: line.text)
                            .font(OrzMCTheme.Typography.console)
                            .foregroundStyle(color(for: line.kind))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                            .id(line.id)
                    }
                }
                .padding(OrzMCTheme.Spacing.xs)
            }
            .frame(minHeight: 140, maxHeight: 220)
            .consoleSurface()
            .onChange(of: model.consoleLines.count) {
                if let last = model.consoleLines.last { proxy.scrollTo(last.id, anchor: .bottom) }
            }
        }
    }

    private func color(for kind: SelfHostedServerModel.ConsoleLine.Kind) -> Color {
        switch kind {
        case .command: return OrzMCTheme.Palette.accent
        case .output: return Color.primary
        case .error: return OrzMCTheme.Palette.danger
        }
    }

    private func send() {
        Task { await model.sendCommand() }
    }

    // MARK: - 还没配置

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.sm) {
            Label("Connect a server you run yourself", systemImage: "server.rack")
                .font(.headline)
            Text("Enter the address and port of a Minecraft server you host (for example one started with `orzmc` in server mode). The app checks its status with Server List Ping; turn on RCON to run console commands.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add Server Address…") { showSettings = true }
                .buttonStyle(.borderedProminent)
        }
        .padding(OrzMCTheme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .orzMCPanel()
    }
}

#Preview {
    NavigationStack {
        SelfHostedServerView()
    }
}
