//
//  ExarotonServerModel+WebSocket.swift
//  OrzMC
//
//  Created by joker on 2024/5/20.
//

import AnyCodable
import Foundation
import ExarotonWebSocket
import OrzMCRemoteHosting

extension ExarotonServerModel {
    /// 连接（或切换）某台服务器的 WebSocket。
    ///
    /// 三个要点（2026-10-22 审查 §B1/B2）：
    /// 1. `callbackQueue` **显式**为 `.main`：模型是 `@MainActor`，隔离性写在代码里，不依赖库默认值；
    /// 2. 每次连接都推进「连接代数」，上一条连接排在队列里的回调会被转发器丢弃；
    /// 3. 回调经 `ExarotonSocketDelegate` 落到模型的 `socketDid*` 方法，不再让模型自己遵守协议
    ///    （那样只能靠 `@preconcurrency` 把跨隔离检查压下去）。
    func startConnect(for serverId: String) {
        if websocket == nil || websocketServerID != serverId {
            connectionEpoch.advance()          // 作废旧连接的在途回调
            websocket?.disconnect()
            websocket = nil
            socketDelegate = nil
            reset()

            let epoch = connectionEpoch.advance()
            let delegate = ExarotonSocketDelegate(model: self, epoch: epoch)
            let socket = ExarotonWebSocketAPI(
                token: token,
                serverId: serverId,
                delegate: delegate,
                callbackQueue: .main
            )
            socketDelegate = delegate
            websocket = socket
            websocketServerID = serverId
        }
        websocket?.connect()
    }

    func stopConnect() {
        // 先作废在途回调，再断开并清状态：顺序反了就会让迟到回调把状态写回来。
        connectionEpoch.advance()
        websocket?.disconnect()
        websocket = nil
        socketDelegate = nil
        websocketServerID = nil
        reset()
    }

    /// 当前代号是否仍是「这条连接」（供转发器校验）。
    func accepts(connectionEpoch epoch: Int) -> Bool {
        connectionEpoch.accepts(epoch)
    }

    func reset() {
        readyServerID = nil
        isConnected = false
        disconnectedReason = nil
        streamStarted = nil
        streamStopped = nil
        activeStreams = []
        consoleLine = nil
        clearConsole()
        tickChanged = nil
        statsChanged = nil
        heapChanged = nil
        statusChangedServer = nil
        statusVersion &+= 1
    }

    // MARK: - 流订阅

    /// 按「已 ready + 已连接 + 服务端在线」的期望状态开/关远程流。
    ///
    /// 取代视图里 3 秒一次的轮询：只发缺的那几条指令，状态稳定时什么都不发。
    func reconcileStreams(serverIsOnline: Bool) {
        // `isLive`（ready 也算）而不是 `isConnected`：真机上 onConnected 可能不触发，
        // 只认 isConnected 会让"已握手"的连接永远不订阅流（→ 控制台没日志）。
        let wantsStreams = readyServerID != nil
            && RemoteStreamingPolicy.shouldStream(isConnected: isLive, isServerOnline: serverIsOnline)
        let plan = RemoteStreamPlan.make(
            active: activeStreams,
            all: Self.streamCategories,
            isEnabled: wantsStreams
        )
        for stream in plan.start { startStream(stream) }
        for stream in plan.stop { stopStream(stream) }
    }

    func startStream(_ stream: StreamCategory, data: AnyCodable? = nil) {
        do {
            try websocket?.send(message: ExarotonMessage(stream: stream, type: StreamType.start, data: data))
        } catch {
            errorMessage = "Failed to start stream: \(error.localizedDescription)"
        }
    }

    func sendConsoleCmd(_ cmd: AnyCodable) {
        do {
            try websocket?.send(message: ExarotonMessage(stream: .console, type: StreamType.command, data: cmd))
        } catch {
            errorMessage = "Failed to send console command: \(error.localizedDescription)"
        }
    }

    func stopStream(_ stream: StreamCategory) {
        do {
            try websocket?.send(message: ExarotonMessage(stream: stream, type: StreamType.stop, data: nil))
        } catch {
            errorMessage = "Failed to stop stream: \(error.localizedDescription)"
        }
    }
}

// MARK: - 回调（只由 `ExarotonSocketDelegate` 在主线程调用）

extension ExarotonServerModel {
    func socketDidBecomeReady(_ serverID: String?) {
        readyServerID = serverID
    }

    func socketDidConnect() {
        isConnected = true
        disconnectedReason = nil
    }

    func socketDidDisconnect(reason: String?) {
        isConnected = false
        disconnectedReason = reason
        activeStreams = []
    }

    func socketDidReceiveStatus(_ info: ExarotonWebSocket.Server?) {
        statusChangedServer = info
        statusVersion &+= 1
        guard let info else { return }
        // 统一入口：WS 与 HTTP 都从这里更新状态、发事件（重复状态不会打扰订阅者）。
        publishStatus(info.status, for: info.id, source: .webSocket)
    }

    /// 每次 socket 收到消息（含 keep-alive）都算"WS 还活着"，轮询据此判断要不要兜底。
    func socketDidReceiveAnyMessage() { noteWebSocketActivity() }

    func socketDidStartStream(_ stream: StreamCategory?) {
        streamStarted = stream
        if let stream { activeStreams.insert(stream) }
    }

    func socketDidStopStream(_ stream: StreamCategory?) {
        streamStopped = stream
        if let stream { activeStreams.remove(stream) }
    }

    func socketDidReceiveConsoleLine(_ line: String?) {
        guard let line else { return }
        consoleLine = line
        appendConsoleLine(line)
    }

    func socketDidReceiveTick(_ tick: ExarotonWebSocket.Tick?) {
        tickChanged = tick
    }

    func socketDidReceiveStats(_ stats: ExarotonWebSocket.Stats?) {
        statsChanged = stats
    }

    func socketDidReceiveHeap(_ heap: ExarotonWebSocket.Heap?) {
        heapChanged = heap
    }
}
