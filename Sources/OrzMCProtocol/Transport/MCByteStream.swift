//
//  MCByteStream.swift
//  OrzMCProtocol
//

import Foundation
import Socket

/// Minecraft 的两种文本协议（Server List Ping / RCON）共用的**字节流**。
///
/// 抽成协议的目的：
/// 1. 传输可注入——单测用假流喂固定字节，不需要起服务器、不需要网络；
/// 2. 阻塞式 socket 只在后台线程用（`MCServerProbe` 里 `Task.detached`），
///    界面层拿到的是 `async` API。
public protocol MCByteStream: AnyObject, Sendable {
    func connect(host: String, port: Int32) throws
    func write(_ data: Data) throws
    /// 读满 `count` 个字节（`Socket` 只保证"读到一些"，TCP 分段时必须自己凑满）。
    func read(count: Int) throws -> Data
    /// 在 `timeoutMilliseconds` 内**还有没有数据可读**（缓冲里或 socket 上）。
    /// RCON 的多包响应靠它判断"后面还有没有下一包"。
    func hasPendingInput(timeoutMilliseconds: Int) throws -> Bool
    func close()
}

/// 读缓冲：`read(count:)` 可能一次读回**多于**需要的字节（TCP 不按包边界送），
/// 多出来的必须留着给下一次读，否则下一个包会永远等不到数据（真实踩过）。
public struct MCReadBuffer: Sendable {
    public private(set) var storage = Data()

    public init() {}

    public mutating func append(_ data: Data) {
        storage.append(data)
    }

    /// 取够 `count` 个字节就返回；不够返回 `nil`（调用方继续读）。
    public mutating func take(_ count: Int) -> Data? {
        guard storage.count >= count else { return nil }
        let result = Data(storage.prefix(count))
        storage.removeFirst(count)
        return result
    }

    public var isEmpty: Bool { storage.isEmpty }
    public var count: Int { storage.count }

    public mutating func removeAll() { storage.removeAll() }
}

public enum MCStreamError: Error, Equatable {
    /// 对端提前关闭（读到的字节数不够）。
    case connectionClosed
    /// 建连失败（DNS / 超时 / 拒绝）。
    case connectFailed(String)
}

/// 生产用实现：BlueSocket 的阻塞 socket。
public final class SocketByteStream: MCByteStream, @unchecked Sendable {
    private var socket: Socket?
    private var buffer = MCReadBuffer()

    public init() {}

    public func connect(host: String, port: Int32) throws {
        do {
            let socket = try Socket.create(family: .inet, type: .stream, proto: .tcp)
            // 超时：连不上要**尽快**告诉用户，而不是挂到系统默认的 75 秒。
            try socket.connect(to: host, port: port, timeout: 8_000)
            self.socket = socket
        } catch {
            throw MCStreamError.connectFailed("\(host):\(port) — \(error)")
        }
    }

    public func write(_ data: Data) throws {
        guard let socket else { throw MCStreamError.connectionClosed }
        try socket.write(from: data)
    }

    public func read(count: Int) throws -> Data {
        guard let socket, count > 0 else { throw MCStreamError.connectionClosed }
        while true {
            if let ready = buffer.take(count) { return ready }
            var chunk = Data()
            let read = try socket.read(into: &chunk)
            guard read > 0 else { throw MCStreamError.connectionClosed }
            buffer.append(chunk)
        }
    }

    public func hasPendingInput(timeoutMilliseconds: Int) throws -> Bool {
        if !buffer.isEmpty { return true }
        guard let socket else { return false }
        return try socket.isReadableOrWritable(waitForever: false, timeout: UInt(max(0, timeoutMilliseconds))).readable
    }

    public func close() {
        socket?.close()
        socket = nil
        buffer.removeAll()
    }
}
