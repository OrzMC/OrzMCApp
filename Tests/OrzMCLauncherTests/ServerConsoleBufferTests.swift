import XCTest
@testable import OrzMCLauncher

/// 服务端控制台缓冲：**服务端输出是字节块**（半行/多行/带 ANSI），这些都在模型里处理。
final class ServerConsoleBufferTests: XCTestCase {
    func testStripsANSIColors() {
        let raw = "\u{1B}[32m[Server] Done\u{1B}[0m (1.234s)!"
        XCTAssertEqual(
            ServerConsoleBuffer.strippingANSI(raw),
            "[Server] Done (1.234s)!"
        )
    }

    func testSplitsChunksIntoLines() {
        var buffer = ServerConsoleBuffer()
        buffer.append("line1\nline2\nlin")
        XCTAssertEqual(buffer.lines.map(\.text), ["line1", "line2"], "半行要等齐了再出")
        buffer.append("e3\n")
        XCTAssertEqual(buffer.lines.map(\.text), ["line1", "line2", "line3"])
    }

    func testFlushPushesPartialLine() {
        var buffer = ServerConsoleBuffer()
        buffer.append("no newline at end")
        XCTAssertTrue(buffer.lines.isEmpty)
        buffer.flush()
        XCTAssertEqual(buffer.lines.map(\.text), ["no newline at end"])
    }

    func testCarriageReturnReplacesProgressLine() {
        var buffer = ServerConsoleBuffer()
        buffer.append("Progress 10%\rProgress 100%\n")
        // \r 是进度条自刷新：前半行被覆盖，最终只保留最后状态（不留"半行垃圾"）。
        XCTAssertEqual(buffer.lines.map(\.text), ["Progress 100%"])
    }

    func testCapacityDropsOldest() {
        var buffer = ServerConsoleBuffer(capacity: 3)
        for index in 1...5 { buffer.append("l\(index)\n") }
        XCTAssertEqual(buffer.lines.map(\.text), ["l3", "l4", "l5"])
        XCTAssertEqual(buffer.lines.count, 3)
    }

    func testSubmitCommandEchoesAndRecordsHistory() {
        var buffer = ServerConsoleBuffer()
        XCTAssertEqual(buffer.submitCommand("  say hi  "), "say hi", "两侧空白要裁掉")
        XCTAssertEqual(buffer.submitCommand("   "), nil, "空命令不发送")
        XCTAssertEqual(buffer.history, ["say hi"])
        XCTAssertTrue(buffer.lines.last?.isCommand ?? false, "命令要标记成命令行，便于和日志区分")
    }

    func testHistoryDeduplicatesConsecutiveAndCaps() {
        var buffer = ServerConsoleBuffer(historyLimit: 2)
        buffer.submitCommand("a")
        buffer.submitCommand("a")   // 连续重复不重复记
        buffer.submitCommand("b")
        buffer.submitCommand("c")   // 超过上限丢最旧
        XCTAssertEqual(buffer.history, ["b", "c"])
        XCTAssertEqual(buffer.historyEntry(at: 0), "c", "0 = 最近一条")
        XCTAssertEqual(buffer.historyEntry(at: 1), "b")
        XCTAssertNil(buffer.historyEntry(at: 2))
    }

    func testClearKeepsHistory() {
        var buffer = ServerConsoleBuffer()
        buffer.append("log\n")
        buffer.submitCommand("stop")
        buffer.clear()
        XCTAssertTrue(buffer.lines.isEmpty)
        XCTAssertEqual(buffer.history, ["stop"], "清屏不该丢命令历史")
    }

    func testEmptyChunkIsIgnored() {
        var buffer = ServerConsoleBuffer()
        buffer.append("")
        buffer.append("\n")
        XCTAssertTrue(buffer.lines.isEmpty, "空块/纯空行不产生垃圾行")
    }
}
