//
//  ExarotonServerDetail.swift
//  OrzMC
//
//  Created by joker on 2024/5/17.
//

import SwiftUI
import ExarotonWebSocket

struct ExarotonServerDetail: View {

    @Environment(ExarotonServerModel.self) var model

    @State var server: ExarotonServer

    @State private var wsServerReady: Bool = false

    @State private var networkOpacity: Double = 1

    @State private var serverRAM: Int32 = 0

    @State private var loading  = false

    @State private var consoleLog: String = ""

    private let timer = Timer.publish(every: 3, on: .main, in: .common).autoconnect()

    @State private var showConsoleCommandInput = false
    @State private var consoleCommand: String = ""

    var body: some View {

        @Bindable var model = model

        Form {

            Section("General") {
                ExarotonServerView(server: server, showStatus: false, showMotd: true)
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
                            if let tick = model.tickChanged {
                                Text(tick.usageLabel)
                            }
                            if let heap = model.heapChanged {
                                Text(heap.usageLabel)
                            }
                        }
                    }
                }

                Section("Actions") {

                    if serverRAM > 0 {
                        Stepper("RAM: \(String(format: "%d", serverRAM)) GB",
                                value: $serverRAM,
                                in: 2...16,
                                step: 1
                        )
                        .disabled(loading || serverStatus != .OFFLINE)
                    }

                    Button("Start Server", systemImage: "restart.circle") {
                        Task {
                            guard let serverID = server.id else {
                                model.errorMessage = "Server ID is missing."
                                return
                            }
                            await model.startServer(serverId: serverID)
                        }
                    }.disabled(serverStatus != .OFFLINE)

                    Button("Stop Server", systemImage: "stop.fill") {
                        Task {
                            guard let serverID = server.id else {
                                model.errorMessage = "Server ID is missing."
                                return
                            }
                            await model.stopServer(serverId: serverID)
                        }
                    }
                    .disabled(serverStatus != .ONLINE)

                    Button("Restart Server", systemImage: "restart.circle.fill") {
                        Task {
                            guard let serverID = server.id else {
                                model.errorMessage = "Server ID is missing."
                                return
                            }
                            await model.restartServer(serverId: serverID)
                        }
                    }
                    .disabled(serverStatus != .ONLINE)
                }

                if model.isConnected {

                    Section("Console") {

                        ScrollView(.vertical, showsIndicators: true) {
                            Text(consoleLog)
                                .foregroundStyle(Color.white)
                                .font(.system(size: 8))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 100)
                        .listRowBackground(Color.black)
                        .defaultScrollAnchor(.bottom)

                        Button {
                            consoleLog = ""
                        } label: {
                            Text("Clear Console")
                        }

                        Button("Send Console Command") {
                            showConsoleCommandInput = true
                        }
                        .keyboardShortcut(.init("c"), modifiers: .command)
                    }
                }
            }
        }
        .formStyle(GroupedFormStyle())
        .navigationTitle("Server Detail")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItemGroup {
                Image(systemName: wsServerReady ? "checkmark.icloud.fill" : "icloud.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(wsServerReady ? mainColor : dangerColor)
                    .frame(width: 30, height: 30)
                    .opacity(networkOpacity)
                    .animation(wsServerReady ? nil : .easeInOut(duration: 0.8).repeatForever(), value: networkOpacity)

                if let serverStatus = server.serverStatus {
                    ExarotonServerStatusView(status: serverStatus)
                        .frame(width: 25, height: 25)
                }
            }
        }
        .overlay {
            ProgressView()
                .controlSize(.extraLarge)
                .progressViewStyle(.circular)
                .opacity(loading ? 1 : 0)
        }
        .sheet(isPresented: $showConsoleCommandInput) {
            if !consoleCommand.isEmpty {
                let validCommand = consoleCommand.trimmingCharacters(in: .whitespacesAndNewlines)
                model.sendConsoleCmd(.init(validCommand))
                consoleCommand = ""
            }
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                Text("Input Command")
                    .font(.headline)
                    .frame(minWidth: 300, alignment: .leading)

                TextEditor(text: $consoleCommand)
                    .scrollContentBackground(.hidden)
                    .background(Color.black)
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .autocorrectionDisabled()
#if os(macOS)
                    .frame(maxWidth: 400, minHeight: 100)
#endif
#if os(iOS)
                    .keyboardType(.alphabet)
                    .textInputAutocapitalization(.never)
#endif
            }
            .padding()
            .onSubmit {
                showConsoleCommandInput = false
            }
            .presentationDragIndicator(.visible)
            .presentationDetents([.height(300)])
            .presentationCornerRadius(10)
            .presentationCompactAdaptation(horizontal: .none, vertical: .sheet)
        }
        .task {
            guard let serverID = server.id else {
                model.errorMessage = "Server ID is missing."
                return
            }
            model.startConnect(for: serverID)
            wsServerReady = model.readyServerID != nil
            networkOpacity = wsServerReady ? 1 : 0
            if let ram = await model.getRAM(serverId: serverID) {
                serverRAM = ram
            }
        }
        .onDisappear {
            model.stopConnect()
        }
        .onChange(of: model.readyServerID) { oldValue, newValue in
            wsServerReady = newValue != nil
            networkOpacity = wsServerReady ? 1 : 0
        }
        .onChange(of: serverRAM, initial: false) { oldValue, newValue in
            guard let serverID = server.id
            else {
                return
            }
            Task {
                loading = true
                if let ram = await model.changeRAM(serverId: serverID, ramGB: newValue) {
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

    func startStreams() {
        Self.actionStreams.forEach { model.startStream($0) }
    }

    func stopStreams() {
        Self.actionStreams.forEach { model.stopStream($0) }
    }
}
