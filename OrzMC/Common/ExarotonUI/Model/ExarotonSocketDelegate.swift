//
//  ExarotonSocketDelegate.swift
//  OrzMC
//

import ExarotonWebSocket
import Foundation
import Starscream

/// 带「连接代数」的 WebSocket 回调转发器。
///
/// 为什么需要它：`ExarotonWebSocketAPI` 用 `callbackQueue.async` 投递回调，
/// `disconnect()` + `reset()` 之后仍可能有**上一条连接**的回调排在主队列里；
/// 直接执行就会把已经清空的状态写回来（例如离开详情页后仍显示上一次的断线原因）。
///
/// 做法：每个连接一个转发器，带着创建时的代号；回调先校验代号再落到模型。
///
/// 隔离性说明：回调队列在 `ExarotonServerModel.startConnect` 里**显式指定为 `.main`**，
/// 所以这里把转发器本身标成 `@MainActor`；`@preconcurrency` 只在这个「库还是并发前的 API」
/// 接缝上使用一次（模型本身不再遵守协议、也不再需要它），并且每次回调都先校验连接代数。
@MainActor
final class ExarotonSocketDelegate: @preconcurrency ExarotonServerEventHandlerProtocol {
    private weak var model: ExarotonServerModel?
    private let epoch: Int

    init(model: ExarotonServerModel, epoch: Int) {
        self.model = model
        self.epoch = epoch
    }

    // MARK: - ExarotonServerEventHandlerProtocol

    func onReady(serverID: String?) {
        forward { $0.socketDidBecomeReady(serverID) }
    }

    func onConnected() {
        forward { $0.socketDidConnect() }
    }

    func onDisconnected(reason: String?) {
        forward { $0.socketDidDisconnect(reason: reason) }
    }

    func onKeepAlive() {
        forward { $0.socketDidReceiveAnyMessage() }
    }

    func onStatusChanged(_ info: ExarotonWebSocket.Server?) {
        forward { $0.socketDidReceiveStatus(info) }
    }

    func onStreamStarted(_ stream: StreamCategory?) {
        forward { $0.socketDidStartStream(stream) }
    }

    func onStreamStopped(_ stream: StreamCategory?) {
        forward { $0.socketDidStopStream(stream) }
    }

    func onConsoleLine(_ line: String?) {
        forward { $0.socketDidReceiveConsoleLine(line) }
    }

    func onTick(_ tick: ExarotonWebSocket.Tick?) {
        forward { $0.socketDidReceiveTick(tick) }
    }

    func onStats(_ stats: ExarotonWebSocket.Stats?) {
        forward { $0.socketDidReceiveStats(stats) }
    }

    func onHeap(_ heap: ExarotonWebSocket.Heap?) {
        forward { $0.socketDidReceiveHeap(heap) }
    }

    func didReceive(event: Starscream.WebSocketEvent, client: any Starscream.WebSocketClient) {
        // 语义回调由 onConnected / onStatusChanged 等承载；这里只记"WS 收到了东西"，
        // 供 `RemoteStatusRefreshPolicy` 判断 WS 是否还活着（安静 30 秒就由轮询接管）。
        switch event {
        case .text, .ping, .pong, .viabilityChanged:
            forward { $0.socketDidReceiveAnyMessage() }
        default:
            break
        }
    }

    // MARK: - 转发

    private func forward(_ body: (ExarotonServerModel) -> Void) {
        guard let model, model.accepts(connectionEpoch: epoch) else { return }
        body(model)
    }
}
