//
//  MCServerProbe.swift
//  OrzMCProtocol
//

import Foundation

public enum MCProbeError: Error, Equatable {
    /// 超时（连不上或对端一直不回包）。
    case timedOut
}

/// 对一个自建服务器做两件事（都是阻塞 TCP + 自定义二进制协议）：
///
/// - `status(host:port:)`：Server List Ping（跟游戏里"多人游戏列表"看到的是同一份数据）；
/// - `runRCON(host:port:password:command:)`：RCON 执行一条控制台命令。
///
/// 对外只有 `async` API：阻塞调用放到**专用队列**（不是 `Task.detached`，那会占住并发线程池），
/// 并且有硬超时——连不上或对端不回话时要尽快失败，否则界面会一直停在「检查中…」。
/// 传输层可注入（`streamFactory`），单测用假流即可覆盖分包/超时/结构异常。
public struct MCServerProbe: Sendable {
    public typealias StreamFactory = @Sendable () -> MCByteStream

    private let streamFactory: StreamFactory

    /// 阻塞 IO 专用队列（并发）。不用 `Task.detached`：阻塞调用会占住 Swift 并发的协作线程，
    /// 线程池被占满后连"超时计时"都调度不起来（实测 2 秒超时被拖到 8 秒）。
    private static let ioQueue = DispatchQueue(
        label: "orzmc.protocol.io",
        qos: .userInitiated,
        attributes: .concurrent
    )

    public init(streamFactory: @escaping StreamFactory = { SocketByteStream() }) {
        self.streamFactory = streamFactory
    }

    // MARK: - Server List Ping

    public func status(host: String, port: Int32, timeout: Duration = .seconds(10)) async throws -> MCStatusSummary {
        try await withStream(timeout: timeout) { stream in
            try Self.performStatus(host: host, port: port, stream: stream)
        }
    }

    // MARK: - RCON

    /// 登录 + 执行一条命令，返回服务端输出（多包响应只取第一条，够用于 `list` / `say` 这类）。
    public func runRCON(
        host: String,
        port: Int32,
        password: String,
        command: String,
        timeout: Duration = .seconds(10)
    ) async throws -> String {
        try await withStream(timeout: timeout) { stream in
            try Self.performRCON(
                host: host,
                port: port,
                password: password,
                command: command,
                stream: stream
            )
        }
    }

    // MARK: - 调度

    private func withStream<T: Sendable>(
        timeout: Duration,
        _ body: @escaping @Sendable (MCByteStream) throws -> T
    ) async throws -> T {
        let stream = streamFactory()
        return try await RaceWithTimeout.run(
            timeout: timeout,
            // 超时后关 socket：卡在 read 的线程会立刻报错退出（不用等它自己超时）。
            onTimeout: { stream.close() },
            work: { [self] in try await runBlocking { try body(stream) } }
        )
    }

    private func runBlocking<T: Sendable>(_ body: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            Self.ioQueue.async {
                continuation.resume(with: Result { try body() })
            }
        }
    }

    // MARK: - SLP 协议

    private static func performStatus(host: String, port: Int32, stream: MCByteStream) throws -> MCStatusSummary {
        defer { stream.close() }
        try stream.connect(host: host, port: port)

        // 1) handshake（next state = 1 = status）
        let handshake = MCSLPPacket()
        handshake.writeID(0x00)
        handshake.writeVarInt(value: -1)
        handshake.writeString(value: host)
        handshake.writeUnsignedShort(value: UInt16(truncatingIfNeeded: port))
        handshake.writeVarInt(value: 1)
        handshake.encapsulate()
        try stream.write(handshake.data)

        // 2) status request
        let request = MCSLPPacket()
        request.writeID(0x00)
        request.encapsulate()
        try stream.write(request.data)

        // 3) 读响应：VarInt 长度 + 包体（必须读满，TCP 会分段）
        let body = try readPacket(stream: stream)
        // `body` 已经去掉长度前缀，第一个字节就是 packetID。
        let response = MCSLPPacket(data: body)
        guard response.readID() != nil else { throw MCSLPError.packetMalFormat }
        guard let json = try response.readString() else { throw MCSLPError.packetMalFormat }

        // 4) ping/pong：测时延；失败不影响状态展示
        let latency = (try? measurePing(stream: stream)) ?? 0
        return try MCStatusSummary.parse(statusJSON: json, latencyMilliseconds: latency)
    }

    private static func measurePing(stream: MCByteStream) throws -> Int {
        let ping = MCSLPPacket()
        ping.writeID(0x01)
        ping.writeLong(value: Int64.max)
        ping.encapsulate()

        let start = Date()
        try stream.write(ping.data)
        let body = try readPacket(stream: stream)
        let pong = MCSLPPacket(data: body)
        guard pong.readID() != nil else { throw MCSLPError.pingFailed }
        return max(0, Int(Date().timeIntervalSince(start) * 1000))
    }

    /// 读一个「VarInt 长度 + 包体」的完整包（返回包体，不含长度前缀）。
    private static func readPacket(stream: MCByteStream) throws -> Data {
        let length = try readVarInt(stream: stream)
        guard length >= 0, length <= 4 * 1024 * 1024 else { throw MCSLPError.packetMalFormat }
        return try stream.read(count: length)
    }

    private static func readVarInt(stream: MCByteStream) throws -> Int {
        var value = 0
        var shift = 0
        while true {
            let byte = try stream.read(count: 1)[0]
            value |= Int(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return value }
            shift += 7
            if shift > 28 { throw MCSLPError.VarIntTooBig }
        }
    }

    // MARK: - RCON 协议

    private static func performRCON(
        host: String,
        port: Int32,
        password: String,
        command: String,
        stream: MCByteStream
    ) throws -> String {
        defer { stream.close() }
        try stream.connect(host: host, port: port)

        // auth
        let auth = RCONPacket(id: 1, type: .auth, body: password)
        try stream.write(auth.data)
        let authPacket = try readRCONPacket(stream: stream)
        guard let authPacket else { throw MCRCONError.packetMalFormat }
        guard authPacket.type == .command, authPacket.id == 1 else {
            // 密码错时服务端会回 id = -1
            throw MCRCONError.authFailed
        }

        let request = RCONPacket(id: 2, type: .command, body: command)
        try stream.write(request.data)

        // 返回可能是**多个包**（长输出会拆包：`help` / `list` 人多时）。
        // 第一包必须读；之后在 120ms 内还有数据就继续读，直到没有为止。
        var chunks: [String] = []
        var isFirst = true
        while isFirst || (try? stream.hasPendingInput(timeoutMilliseconds: 120)) == true {
            guard let packet = try readRCONPacket(stream: stream) else { throw MCRCONError.packetMalFormat }
            guard packet.type == .response else { throw MCRCONError.responseInvalid }
            let body = packet.body
            if !body.isEmpty { chunks.append(body) }
            isFirst = false
        }
        return chunks.joined(separator: "\n")
    }

    private static func readRCONPacket(stream: MCByteStream) throws -> RCONPacket? {
        let lengthBytes = try stream.read(count: 4)
        let length = Int(Int32(littleEndian: lengthBytes.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }))
        guard length >= 10, length <= 1024 * 1024 else { throw MCRCONError.packetMalFormat }
        let body = try stream.read(count: length)
        return RCONPacket(data: lengthBytes + body)
    }
}
