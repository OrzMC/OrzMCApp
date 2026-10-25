import OrzMCFoundation
import XCTest
@testable import OrzMCRemoteHosting

final class RemoteConsoleBufferTests: XCTestCase {
    func testClearThenReceiveDoesNotRestoreOldOutput() {
        var buffer = RemoteConsoleBuffer()
        buffer.append("old output\n")
        let oldID = buffer.lines.last!.id
        buffer.clear()
        buffer.append("new output\n")
        XCTAssertEqual(buffer.lines.map(\.text), ["new output"])
        XCTAssertGreaterThan(buffer.lines[0].id, oldID)
    }

    func testFullBufferKeepsStableIDsAsOutputArrives() {
        var buffer = RemoteConsoleBuffer(capacity: RemoteConsoleBuffer.defaultCapacity)
        for index in 0..<2001 { buffer.append("\(index)") }
        XCTAssertEqual(buffer.lines.count, 2000)
        XCTAssertEqual(buffer.lines.first?.text, "1")
        XCTAssertEqual(buffer.lines.last?.text, "2000")
        XCTAssertEqual(Set(buffer.lines.map(\.id)).count, 2000)
        let retainedID = buffer.lines[1].id
        buffer.append("2001")
        XCTAssertEqual(buffer.lines.first?.id, retainedID)
        XCTAssertEqual(buffer.lines.last?.id, 2001)
    }

    // MARK: - 多行 / 颜色（P2-6 起由共享解析器处理）

    func testMultiLineMessageSplitsIntoLines() {
        var buffer = RemoteConsoleBuffer()
        buffer.append("[20:11:02] [Server thread/INFO]: Starting\n[20:11:07] [Server thread/INFO]: Done\n")
        XCTAssertEqual(buffer.lines.count, 2, "一条消息里的多行要拆开")
        XCTAssertEqual(buffer.lines.last?.text, "[20:11:07] [Server thread/INFO]: Done")
    }

    func testANSIColorsAreParsedNotDropped() {
        var buffer = RemoteConsoleBuffer()
        buffer.append("\u{1B}[32mINFO\u{1B}[0m started\n\u{1B}[33mWARN\u{1B}[0m lag")
        XCTAssertEqual(buffer.lines.map(\.text), ["INFO started", "WARN lag"], "文本里不许残留 ESC")
        XCTAssertEqual(buffer.lines[0].segments, [
            ConsoleTextSegment(text: "INFO", color: .green),
            ConsoleTextSegment(text: " started"),
        ])
        XCTAssertEqual(buffer.lines[1].segments.first?.color, .yellow)
    }

    /// **回归**：一条消息以 `\r` 结尾时必须照常显示（exaroton 的 console 流就是这样）。
    func testLinesEndingWithCarriageReturnAreNotDropped() {
        var buffer = RemoteConsoleBuffer()
        buffer.append("[20:11:02] [Server thread/INFO]: Done (9.874s)!\r")
        buffer.append("\u{1B}[32m[20:11:07] [Server thread/INFO]\u{1B}[0m: Joined\r")
        XCTAssertEqual(buffer.lines.map(\.text), [
            "[20:11:02] [Server thread/INFO]: Done (9.874s)!",
            "[20:11:07] [Server thread/INFO]: Joined",
        ])
        XCTAssertEqual(buffer.lines[1].segments.first?.color, .green)
    }

    func testCarriageReturnOverwriteCollapsesProgress() {
        var buffer = RemoteConsoleBuffer()
        buffer.append("10%\r50%\r100%\n")
        XCTAssertEqual(buffer.lines.map(\.text), ["100%"])
    }

    func testEmptyAndWhitespaceOnlyMessagesAreIgnored() {
        var buffer = RemoteConsoleBuffer()
        buffer.append("\n\n   \n")
        XCTAssertTrue(buffer.lines.isEmpty)
    }
}
