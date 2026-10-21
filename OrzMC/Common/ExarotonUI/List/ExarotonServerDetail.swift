//
//  ExarotonServerDetail.swift
//  OrzMC
//
//  Created by joker on 2024/5/17.
//

import ExarotonWebSocket
import OrzMCDesignSystem
import SwiftUI

struct ExarotonServerDetail: View {

    @Environment(ExarotonServerModel.self) var model

    @State var server: ExarotonServer

    @State private var wsServerReady: Bool = false

    @State private var serverRAM: Int32 = 0
    /// 服务器当前确认的 RAM（来自 GET / 变更成功后的返回值）。
    /// 用它区分“加载时赋值”和“用户拖动 Stepper”，避免加载完又多发一次 changeRAM。
    @State private var confirmedRAM: Int32?

    @State private var loading  = false

    @State private var consoleLog: String = ""

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    @State private var showConsoleCommandInput = false
    @State private var consoleCommand: String = ""

    var body: some View {

        @Bindable var model = model

        Form {

            Section("General") {
                ExarotonServerView(server: server, showStatus: true, showMotd: true)
            }

            if let playlist = server.players?.list, !playlist.isEmpty {
                Section("Playlist") {
                    ExarotonServerPlayList(playlist: playlist)
                }
            }

            if let serverStatus = server.serverStatus {

                if model.isConnected {
                    Section("Metrics") {
                        VStack(alignment: .center, spacing: 10) {
                            if let stats = model.statsChanged {
                                HStack(alignment: .center, spacing: 20) {
                                    Gauge(value: stats.cpuUsage, in: stats.cpuUsageRange) {
                                        Text(stats.cpuUsageLabel)
                                    } currentValueLabel: {
                                        Text(stats.cpuUsageDesc)
                                    }
                                    Gauge(value: stats.memUsage, in: stats.memUsageRange) {
                                        Text(stats.memUsageLabel)
                                    } currentValueLabel: {
                                        Text(stats.memUsageDesc)
                                    }
                                }
                            }
                            HStack(spacing: OrzMCTheme.Spacing.xs) {
                                if let tick = model.tickChanged {
                                    OrzMCTag(tick.usageLabel)
                                }
                                if let heap = model.heapChanged {
                                    OrzMCTag(heap.usageLabel)
                                }
                            }
                        }
                    }
                }

                ExarotonServerActionSection(
                    server: server,
                    status: serverStatus,
                    serverRAM: $serverRAM,
                    isLoading: $loading
                )

                if model.isConnected {

                    Section("Console") {

                        ScrollView(.vertical, showsIndicators: true) {
                            Text(consoleLog)
                                .font(OrzMCTheme.Typography.console)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 160)
                        .consoleSurface()
                        .defaultScrollAnchor(.bottom)

                        HStack(spacing: OrzMCTheme.Spacing.sm) {
                            Button("Send Console Command…", systemImage: "paperplane") {
                                showConsoleCommandInput = true
                            }
                            .buttonStyle(.borderedProminent)

                            Button("Clear Console", systemImage: "trash") {
                                consoleLog = ""
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(server.name ?? String(localized: "Server Detail"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItemGroup {
                Image(systemName: wsServerReady ? "checkmark.icloud.fill" : "icloud.slash")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(wsServerReady ? OrzMCTheme.Palette.success : OrzMCTheme.Palette.danger)
                    .symbolEffect(.pulse, options: .repeating, isActive: !wsServerReady)
                    .help(wsServerReady ? "Connected to the server console" : "Connecting to the server console…")
                    .accessibilityLabel(wsServerReady ? "Connected" : "Connecting")

                if let serverStatus = server.serverStatus {
                    ExarotonServerStatusView(status: serverStatus)
                        .frame(width: 25, height: 25)
                }
            }
        }
        .overlay {
            if loading {
                ProgressView()
                    .controlSize(.extraLarge)
                    .padding(OrzMCTheme.Spacing.lg)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: OrzMCTheme.Radius.md))
            }
        }
        .sheet(isPresented: $showConsoleCommandInput) {
            // 命令只在用户点「Send」时发送；以前把发送逻辑写在 sheet 的 content builder 里，
            // 等于“一打开就发”，而且是在 body 里改状态（SwiftUI 会报警告）。
            VStack(alignment: .leading, spacing: OrzMCTheme.Spacing.md) {
                Text("Send Console Command")
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .leading)

                TextEditor(text: $consoleCommand)
                    .font(OrzMCTheme.Typography.consoleInput)
                    .scrollContentBackground(.hidden)
                    .padding(OrzMCTheme.Spacing.xs)
                    .consoleSurface(cornerRadius: OrzMCTheme.Radius.md)
                    .autocorrectionDisabled()
#if os(macOS)
                    .frame(maxWidth: 400, minHeight: 100)
#endif
#if os(iOS)
                    .keyboardType(.alphabet)
                    .textInputAutocapitalization(.never)
#endif

                HStack {
                    Spacer()
                    Button("Cancel", role: .cancel) {
                        consoleCommand = ""
                        showConsoleCommandInput = false
                    }
                    Button("Send") {
                        sendConsoleCommand()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(consoleCommand.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(OrzMCTheme.Spacing.lg)
            .presentationDragIndicator(.visible)
            .presentationDetents([.height(300)])
            .presentationCornerRadius(OrzMCTheme.Radius.md)
            .presentationCompactAdaptation(horizontal: .none, vertical: .sheet)
        }
        .task {
            guard let serverID = server.id else {
                model.errorMessage = "Server ID is missing."
                return
            }
            model.startConnect(for: serverID)
            wsServerReady = model.readyServerID != nil
            if let ram = await model.getRAM(serverId: serverID) {
                confirmedRAM = ram
                serverRAM = ram
            }
        }
        .onDisappear {
            model.stopConnect()
        }
        .onChange(of: model.readyServerID) { _, newValue in
            wsServerReady = newValue != nil
        }
        .onChange(of: serverRAM, initial: false) { _, newValue in
            guard newValue != confirmedRAM, let serverID = server.id else { return }
            Task {
                loading = true
                if let ram = await model.changeRAM(serverId: serverID, ramGB: newValue) {
                    confirmedRAM = ram
                    serverRAM = ram
                }
                loading = false
            }
        }
        .onReceive(model.consoleLine.publisher.throttle(for: 1, scheduler: RunLoop.main, latest: true)) { _ in
            consoleLog = model.consoleLines.joined(separator: "")
        }
        .onReceive(model.statusChangedServer.publisher) { newStatusServer in
            guard let serverInfo = try? newStatusServer.serverInfo
            else {
                return
            }
            server = serverInfo
        }
        .onReceive(timer) { _ in
            guard wsServerReady, model.isConnected == false,
                  let serverStatus = server.serverStatus, serverStatus == .ONLINE
            else {
                return
            }
            startStreams()
        }
        .onReceive(timer) { _ in
            guard wsServerReady, model.isConnected == true,
                  let serverStatus = server.serverStatus, serverStatus == .OFFLINE
            else {
                return
            }
            stopStreams()
        }
    }
}

extension ExarotonServerDetail {

    static let actionStreams = StreamCategory.allCases.filter { $0 != .status }

    private func sendConsoleCommand() {
        let validCommand = consoleCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !validCommand.isEmpty else { return }
        model.sendConsoleCmd(.init(validCommand))
        consoleCommand = ""
        showConsoleCommandInput = false
    }

    func startStreams() {
        Self.actionStreams.forEach { model.startStream($0) }
    }

    func stopStreams() {
        Self.actionStreams.forEach { model.stopStream($0) }
    }
}
