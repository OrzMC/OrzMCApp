import Foundation
import XCTest

@testable import OrzMCProtocol

/// SLP / RCON 的可测性：传输层注入假流，不需要网络和真实服务端。
final class MCServerProbeTests: XCTestCase {

    // MARK: - 假字节流

    /// 按"服务端会发什么"预置响应；写出去的字节记录下来供断言。
    final class FakeStream: MCByteStream, @unchecked Sendable {
        private var incoming: [UInt8]
        private(set) var written = Data()
        private(set) var closed = false
        var connectError: Error?
        /// `hasPendingInput` 的返回值（模拟"还没读完的多包响应"）。
        var pendingAfterReads: Bool
        let host: String?
        let port: Int32?

        init(
            incoming: [UInt8] = [],
            host: String? = nil,
            port: Int32? = nil,
            connectError: Error? = nil,
            pendingAfterReads: Bool = false
        ) {
            self.incoming = incoming
            self.host = host
            self.port = port
            self.connectError = connectError
            self.pendingAfterReads = pendingAfterReads
        }

        func connect(host: String, port: Int32) throws {
            if let connectError { throw connectError }
        }

        func write(_ data: Data) throws { written.append(data) }

        func read(count: Int) throws -> Data {
            guard incoming.count >= count else { throw MCStreamError.connectionClosed }
            let slice = Array(incoming.prefix(count))
            incoming.removeFirst(count)
            return Data(slice)
        }

        func hasPendingInput(timeoutMilliseconds: Int) throws -> Bool {
            // 预置数据还没读完 → 还有；否则用调用方给的开关（模拟"后面没有更多包了"）。
            if !incoming.isEmpty { return true }
            return pendingAfterReads
        }

        func close() { closed = true }
    }

    // MARK: - 构包工具

    private static func varInt(_ value: Int) -> [UInt8] {
        var value = value
        var bytes = [UInt8]()
        repeat {
            var byte = UInt8(value & 0x7F)
            value >>= 7
            if value != 0 { byte |= 0x80 }
            bytes.append(byte)
        } while value != 0
        return bytes
    }

    /// 「包长度 + packetID + 字符串」的 SLPPacket 包。
    private static func slpStringPacket(id: UInt8, _ text: String) -> [UInt8] {
        let utf8 = Array(text.utf8)
        var body: [UInt8] = [id] + varInt(utf8.count) + utf8
        body = varInt(body.count) + body
        return body
    }

    private static func slpPongPacket() -> [UInt8] {
        // packetID 0x01 + Int64 max
        let id: UInt8 = 0x01
        var payload: [UInt8] = [id]
        payload.append(contentsOf: [0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x7F])
        return varInt(payload.count) + payload
    }

    private static func rconPacket(id: Int32, type: Int32, body: String) -> [UInt8] {
        var payload = [UInt8]()
        payload.append(contentsOf: withUnsafeBytes(of: id.littleEndian) { Array($0) })
        payload.append(contentsOf: withUnsafeBytes(of: type.littleEndian) { Array($0) })
        payload.append(contentsOf: Array(body.utf8))
        payload.append(0x00)
        payload.append(0x00)
        var bytes = withUnsafeBytes(of: Int32(payload.count).littleEndian) { Array($0) }
        bytes.append(contentsOf: payload)
        return bytes
    }

    // MARK: - 状态解析

    func testParsesFlatDescription() throws {
        let json = #"{"version":{"name":"1.21.4","protocol":769},"players":{"max":20,"online":3,"sample":[{"name":"joker","id":"x"}]},"description":"Hello"}"#
        let summary = try MCStatusSummary.parse(statusJSON: json, latencyMilliseconds: 42)
        XCTAssertEqual(summary.versionName, "1.21.4")
        XCTAssertEqual(summary.protocolVersion, 769)
        XCTAssertEqual(summary.playersOnline, 3)
        XCTAssertEqual(summary.playersMax, 20)
        XCTAssertEqual(summary.sampleNames, ["joker"])
        XCTAssertEqual(summary.motd, "Hello")
        XCTAssertEqual(summary.latencyMilliseconds, 42)
    }

    func testParsesNestedDescriptionAndStripsColorCodes() throws {
        let json = #"{"description":{"text":"§aHello ","extra":[{"text":"world"}]}}"#
        let summary = try MCStatusSummary.parse(statusJSON: json)
        XCTAssertEqual(summary.motd, "Hello world")
    }

    func testToleratesMissingOptionalFields() throws {
        let summary = try MCStatusSummary.parse(statusJSON: #"{"description":"hi"}"#)
        XCTAssertNil(summary.versionName)
        XCTAssertNil(summary.playersOnline)
        XCTAssertEqual(summary.sampleNames, [])
    }

    func testMalformedJSONThrows() {
        XCTAssertThrowsError(try MCStatusSummary.parse(statusJSON: "not json"))
    }

    // MARK: - Server List Ping

    func testStatusReadsHandshakeThenParsesReply() async throws {
        let json = #"{"version":{"name":"1.21.4","protocol":769},"players":{"max":10,"online":1},"description":"Hi"}"#
        let stream = FakeStream(incoming: Self.slpStringPacket(id: 0x00, json) + Self.slpPongPacket())
        let probe = MCServerProbe(streamFactory: { stream })

        let summary = try await probe.status(host: "mc.example.com", port: 25565)
        XCTAssertEqual(summary.versionName, "1.21.4")
        XCTAssertEqual(summary.playersMax, 10)

        // handshake + status request + ping 都写进去了（3 个包）
        XCTAssertGreaterThan(stream.written.count, 3)
        XCTAssertTrue(stream.closed)
    }

    /// 回归：JSON 长度 > 127 时字符串长度是 **多字节 varint**。
    /// 以前 `value` 用 UInt8 左移 7 位会溢出丢掉高位（278 被读成 22），解析直接失败。
    func testStatusWithLongReplyUsesMultiByteVarint() async throws {
        let longMotd = String(repeating: "a", count: 400)
        let json = #"{"version":{"name":"1.21.9","protocol":770},"players":{"max":10,"online":0},"description":"\#(longMotd)"}"#
        XCTAssertGreaterThan(json.utf8.count, 127, "用例前提：回复要超过 127 字节")

        let stream = FakeStream(incoming: Self.slpStringPacket(id: 0x00, json) + Self.slpPongPacket())
        let summary = try await MCServerProbe(streamFactory: { stream }).status(host: "h", port: 1)
        XCTAssertEqual(summary.versionName, "1.21.9")
        XCTAssertEqual(summary.motd?.count, 400)
    }

    func testStatusPropagatesConnectFailure() async {
        struct Boom: Error {}
        let probe = MCServerProbe(streamFactory: { FakeStream(connectError: Boom()) })
        do {
            _ = try await probe.status(host: "127.0.0.1", port: 1)
            XCTFail("should throw")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }

    // MARK: - RCON

    func testRCONLoginAndCommand() async throws {
        let stream = FakeStream(incoming:
            Self.rconPacket(id: 1, type: 2, body: "")        // auth ok
            + Self.rconPacket(id: 2, type: 0, body: "There are 1 of a max of 10 players online")
        )
        let probe = MCServerProbe(streamFactory: { stream })

        let reply = try await probe.runRCON(
            host: "127.0.0.1", port: 25575, password: "secret", command: "list"
        )
        XCTAssertEqual(reply, "There are 1 of a max of 10 players online")
        XCTAssertTrue(stream.closed)
    }

    /// 长输出会被服务端拆成多个响应包：必须全部读回来（以前只取第一个）。
    func testRCONJoinsMultipleResponsePackets() async throws {
        let stream = FakeStream(
            incoming:
                Self.rconPacket(id: 1, type: 2, body: "")
                + Self.rconPacket(id: 2, type: 0, body: "line one")
                + Self.rconPacket(id: 2, type: 0, body: "line two")
        )
        let probe = MCServerProbe(streamFactory: { stream })
        let reply = try await probe.runRCON(host: "127.0.0.1", port: 25575, password: "s", command: "help")
        XCTAssertEqual(reply, "line one\nline two")
        XCTAssertTrue(stream.closed)
    }

    func testRCONWrongPasswordFails() async {
        let stream = FakeStream(incoming: Self.rconPacket(id: -1, type: 2, body: ""))
        let probe = MCServerProbe(streamFactory: { stream })
        do {
            _ = try await probe.runRCON(host: "127.0.0.1", port: 25575, password: "nope", command: "list")
            XCTFail("should throw")
        } catch {
            XCTAssertEqual(error as? MCRCONError, .authFailed)
        }
    }
}
