//
//  ExarotonServerModel+WebSocket.swift
//  OrzMC
//
//  Created by joker on 2024/5/20.
//

import Foundation
import ExarotonWebSocket
import Starscream
import AnyCodable

extension ExarotonServerModel {
    func startConnect(for serverId: String) {
        if websocket == nil || websocketServerID != serverId {
            websocket?.disconnect()
            websocket = ExarotonWebSocketAPI(token: token, serverId: serverId, delegate: self)
            websocketServerID = serverId
        }
        websocket?.connect()
    }
    func stopConnect() {
        websocket?.disconnect()
        websocket = nil
        websocketServerID = nil
        reset()
    }
    func reset() {
        readyServerID = nil
        isConnected = false
        disconnectedReason = nil
        streamStarted = nil
        streamStopped = nil
        consoleLine = nil
        consoleLines = [String]()
        tickChanged = nil
        statsChanged = nil
        heapChanged = nil
        statusChangedServer = nil
    }

    func startStream(_ stream: StreamCategory, data: AnyCodable? = nil)  {
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

extension ExarotonServerModel: @preconcurrency ExarotonServerEventHandlerProtocol {

    func onReady(serverID: String?) {
        readyServerID = serverID
    }

    func onConnected() {
        isConnected = true
        disconnectedReason = nil
    }

    func onDisconnected(reason: String?) {
        isConnected = false
        disconnectedReason = reason
    }

    func onKeepAlive() {
        // Ignore
    }

    func onStatusChanged(_ info: ExarotonWebSocket.Server?) {
        statusChangedServer = info
    }

    func onStreamStarted(_ stream: ExarotonWebSocket.StreamCategory?) {
        streamStarted = stream
    }

    func onStreamStopped(_ stream: StreamCategory?) {
        streamStopped = stream
    }

    func onConsoleLine(_ line: String?) {
        guard let line
        else {
            return
        }
        consoleLine = line
        consoleLines.append(line)
    }

    func onTick(_ tick: ExarotonWebSocket.Tick?) {
        tickChanged = tick
    }

    func onStats(_ stats: ExarotonWebSocket.Stats?) {
        statsChanged = stats
    }

    func onHeap(_ heap: ExarotonWebSocket.Heap?) {
        heapChanged = heap
    }

    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        // Do Nothing
    }
}
