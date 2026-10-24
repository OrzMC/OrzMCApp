//
//  ExarotonServerDetail.swift
//  OrzMC
//
//  Created by joker on 2024/5/17.
//

import ExarotonWebSocket
import OrzMCDesignSystem
import OrzMCRemoteHosting
import SwiftUI

struct ExarotonServerDetail: View {

    @Environment(ExarotonServerModel.self) var model

    @State private var server: ExarotonServer

    init(server: ExarotonServer) {
        _server = State(initialValue: server)
    }

    @State private var wsServerReady: Bool = false

    /// 内存的「草稿 / 已确认 / 保存中」状态（测试在 `ServerMemoryStateTests`）。
    /// Stepper 只改草稿；明确保存后才更新确认值，失败时两边都不动。
    @State private var memory = ServerMemoryState()
    /// 刚提交的内存值 + 忽略旧回传的时间窗：保存成功后服务端还会推一次"旧值"，
    /// 直接 `loaded(old)` 会让界面先跳回改前、再跳到改后（真机反馈的"跳变"）。
    @State private var lastRequestedRAM: Int32?
    @State private var ignoreMemoryEchoUntil: Date?

    /// 生命周期动作的确认弹窗（挂在本页根部：锚点才会在屏幕底部，而不是某个 Section 行上）。
    @State private var confirmStop = false
    @State private var confirmRestart = false
    @State private var showConsoleCommandInput = false
    @State private var consoleCommand: String = ""

    var body: some View {

        @Bindable var model = model

        Form {

            // 顶部摘要卡与列表行同一个组件：同一个窗口里两处"服务器长什么样"必须一致。
            Section("Overview") {
                ExarotonServerCard(server: server, showMotd: true, showsDisclosure: false)
            }

            // 生命周期动作紧跟概览：这是用户进来最想做的事，别让它排在内存/指标后面
            // （小屏上会滚不到、还容易被浮动 TabBar 压住）。
            if let serverStatus = server.serverStatus {
                ExarotonServerActionSection(
                    server: server,
                    status: serverStatus,
                    confirmStop: $confirmStop,
                    confirmRestart: $confirmRestart
                )
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

                ExarotonMemorySection(
                    serverID: server.id ?? "",
                    serverStatus: serverStatus,
                    memory: memory,
                    onEdit: { newValue in
                        memory.edit(newValue)
                        // 重新编辑即清掉上一次保存失败的错误，避免旧错误挂在新草稿上。
                        model.memoryErrors[server.id ?? ""] = nil
                    },
                    onSave: saveMemory,
                    onRevert: { memory.revert() },
                    onReload: { await loadMemory() }
                )

                if !model.isConnected {
                    consolePlaceholder
                }

                if model.isConnected {

                    Section("Console") {

                        ScrollView(.vertical, showsIndicators: true) {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(model.consoleLines) { line in
                                    Text(verbatim: line.text)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .font(OrzMCTheme.Typography.console)
                            .foregroundStyle(.primary)
                            .textSelection(.enabled)
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
                                model.clearConsole()
                            }
                            .buttonStyle(.bordered)

                            Spacer()
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .labeledContentStyle(.orzMCFieldRow)
        // 破坏性/会断线的远程操作先确认（与本地服务端 Stop/Restart 同一套交互）。
        .confirmationDialog("Stop Server?", isPresented: $confirmStop, titleVisibility: .visible) {
            Button("Stop", role: .destructive) {
                if let id = server.id { Task { _ = await model.stopServer(serverId: id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server saves and shuts down; connected players are disconnected.")
        }
        .confirmationDialog("Restart Server?", isPresented: $confirmRestart, titleVisibility: .visible) {
            Button("Restart") {
                if let id = server.id { Task { _ = await model.restartServer(serverId: id) } }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The server restarts; players are disconnected during the restart.")
        }
        #if os(iOS)
        // iOS 26 的浮动 TabBar 会盖住最后一行（实测把「重启」压住了）。
        // `contentMargins` 对 Form/List 不生效，用 `safeAreaInset` 在底部真正留出空白。
        .safeAreaInset(edge: .bottom) {
            Color.clear.frame(height: 56)
        }
        #endif
        .navigationTitle(server.name ?? String(localized: "Server Detail"))
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItemGroup {
                if let reason = model.disconnectedReason {
                    Button("Reconnect", systemImage: "arrow.clockwise.icloud") {
                        if let id = server.id { model.startConnect(for: id) }
                    }
                    .help(reason)
                } else if !wsServerReady {
                    ProgressView().controlSize(.small)
                        .accessibilityLabel("Connecting")
                }
                // 连接正常时不再往工具栏塞绿色图标，服务器状态也已经由「概览」卡里的徽章表达——
                // 工具栏两个方块图标（云勾 + 状态圆点）在真机上看着像两个不明按钮。
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
                model.errorMessage = String(localized: "Server ID is missing.")
                return
            }
            model.startConnect(for: serverID)
            wsServerReady = model.readyServerID == serverID
            syncStreams()
            await loadMemory()
        }
        .onDisappear {
            model.stopConnect()
        }
        .onChange(of: model.savedMemory[server.id ?? ""]) { _, newValue in
            guard let newValue else { return }
            if let requested = lastRequestedRAM,
               let until = ignoreMemoryEchoUntil,
               Date() < until,
               newValue != requested {
                return       // 保存刚完成，这是滞后回传的旧值，忽略之
            }
            if let requested = lastRequestedRAM, newValue == requested {
                lastRequestedRAM = nil
                ignoreMemoryEchoUntil = nil
            }
            memory.loaded(newValue)
        }
        .onChange(of: model.readyServerID) { _, newValue in
            wsServerReady = newValue == server.id
            syncStreams()
        }
        // 状态推送用「版本号 + onChange」：`Optional.publisher` 只在订阅那一刻发一次，
        // 之前能更新只是靠 body 重算重新订阅，滞后且不可靠。
        .onChange(of: model.statusVersion) {
            applyStatusUpdate()
        }
        .onChange(of: model.isConnected) {
            syncStreams()
        }
        .onChange(of: server.serverStatus) {
            syncStreams()
        }
    }
}

extension ExarotonServerDetail {

    /// 读取内存：成功则同步「确认值 + 草稿」；失败时模型记录 `memoryLoadErrors`，
    /// 动作区会显示「Unavailable + Retry」，且不会把草稿改成一个假的 0。
    private func loadMemory() async {
        guard let id = server.id else { return }
        if let ram = await model.getRAM(serverId: id) {
            memory.loaded(ram)
        }
    }

    private func saveMemory() {
        guard let id = server.id, let requested = memory.beginSave() else { return }
        lastRequestedRAM = requested
        ignoreMemoryEchoUntil = Date().addingTimeInterval(5)
        Task {
            if let ram = await model.changeRAM(serverId: id, ramGB: requested) {
                memory.saveSucceeded(ram)
            } else {
                // 确认值不变、草稿保留：界面继续显示「未保存」，错误由模型就地展示。
                memory.saveFailed()
            }
        }
    }

    private func sendConsoleCommand() {
        let validCommand = consoleCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !validCommand.isEmpty else { return }
        model.sendConsoleCmd(.init(validCommand))
        consoleCommand = ""
        showConsoleCommandInput = false
    }

    /// 未连接时的控制台占位（以前整块消失，用户以为没这个功能）。
    @ViewBuilder
    private var consolePlaceholder: some View {
        Section("Console") {
            HStack(spacing: OrzMCTheme.Spacing.sm) {
                Text("Console needs a live connection to the server.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Reconnect") {
                    if let id = server.id { model.startConnect(for: id) }
                }
            }
            if let reason = model.disconnectedReason {
                Text(verbatim: reason)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    /// 状态推送 → 更新本页展示的服务器摘要。
    private func applyStatusUpdate() {
        guard let latest = model.statusChangedServer,
              let serverInfo = try? latest.serverInfo
        else {
            return
        }
        server = serverInfo
    }

    /// 连接/服务端状态变化时同步远程流：只发缺的那几条，取代原来的 3 秒轮询。
    private func syncStreams() {
        model.reconcileStreams(serverIsOnline: server.serverStatus == .ONLINE)
    }
}
