import XCTest
@testable import OrzMCFoundation

/// 控制台文本解析：ANSI / `§` / 控制字符都不许漏到界面上，颜色与加粗要按 SGR 正确切换。
final class ConsoleTextTests: XCTestCase {

    // MARK: - ANSI SGR

    func testPlainTextHasNoStyle() {
        let segments = ConsoleTextParser.parse("[Server] Done (1.234s)!")
        XCTAssertEqual(segments, [ConsoleTextSegment(text: "[Server] Done (1.234s)!")])
    }

    func testGreenInfoThenReset() {
        let segments = ConsoleTextParser.parse("\u{1B}[32mINFO\u{1B}[0m: started")
        XCTAssertEqual(segments, [
            ConsoleTextSegment(text: "INFO", color: .green),
            ConsoleTextSegment(text: ": started"),
        ])
    }

    func testBoldAndColorCombineAndResetIndependently() {
        let segments = ConsoleTextParser.parse("\u{1B}[1;33mWARN\u{1B}[22m still yellow\u{1B}[39m normal")
        XCTAssertEqual(segments, [
            ConsoleTextSegment(text: "WARN", color: .yellow, isBold: true),
            ConsoleTextSegment(text: " still yellow", color: .yellow),
            ConsoleTextSegment(text: " normal"),
        ])
    }

    func testBrightColorsMapToBrightPalette() {
        XCTAssertEqual(
            ConsoleTextParser.parse("\u{1B}[91mE\u{1B}[0m"),
            [ConsoleTextSegment(text: "E", color: .brightRed)]
        )
        XCTAssertEqual(ConsoleTextParser.parse("\u{1B}[97mW\u{1B}[0m").first?.color, .brightWhite)
        XCTAssertEqual(ConsoleTextParser.parse("\u{1B}[90mK\u{1B}[0m").first?.color, .brightBlack)
    }

    func testEmptySGRMeansReset() {
        let segments = ConsoleTextParser.parse("\u{1B}[31mred\u{1B}[mplain")
        XCTAssertEqual(segments, [
            ConsoleTextSegment(text: "red", color: .red),
            ConsoleTextSegment(text: "plain"),
        ])
    }

    // MARK: - 扩展色

    func test256ColorTable() {
        // 16 = 立方体起点（0,0,0）；196 = 纯红；231 = 纯白；232 = 最深灰阶。
        XCTAssertEqual(ConsoleTextParser.parse("\u{1B}[38;5;196mX\u{1B}[0m").first?.color, .rgb(255, 0, 0))
        XCTAssertEqual(ConsoleTextParser.parse("\u{1B}[38;5;231mX\u{1B}[0m").first?.color, .rgb(255, 255, 255))
        XCTAssertEqual(ConsoleTextParser.parse("\u{1B}[38;5;232mX\u{1B}[0m").first?.color, .rgb(8, 8, 8))
        XCTAssertEqual(ConsoleTextParser.parse("\u{1B}[38;5;2mX\u{1B}[0m").first?.color, .green)
    }

    func testTrueColor() {
        XCTAssertEqual(
            ConsoleTextParser.parse("\u{1B}[38;2;12;34;56mX\u{1B}[0m").first?.color,
            .rgb(12, 34, 56)
        )
    }

    func testBackgroundColorIsIgnoredButDoesNotBecomeForeground() {
        let segments = ConsoleTextParser.parse("\u{1B}[48;5;196mplain")
        XCTAssertEqual(segments, [ConsoleTextSegment(text: "plain")])
    }

    // MARK: - 畸形 / 其它序列

    func testTruncatedEscapeAtEndIsDropped() {
        XCTAssertEqual(ConsoleTextParser.parse("done\u{1B}"), [ConsoleTextSegment(text: "done")])
        XCTAssertEqual(ConsoleTextParser.parse("done\u{1B}["), [ConsoleTextSegment(text: "done")])
        XCTAssertEqual(ConsoleTextParser.parse("\u{1B}[3"), [])
    }

    func testNonSGRCsiSequencesAreDropped() {
        // 清行 + 光标归位 + 光标上移：都只影响终端，不该出现在文本里。
        XCTAssertEqual(
            ConsoleTextParser.parse("\u{1B}[2K\u{1B}[1Gprogress").map(\.text),
            ["progress"]
        )
        XCTAssertEqual(
            ConsoleTextParser.parse("\u{1B}[2Aup\u{1B}[H home").map(\.text),
            ["up home"]
        )
    }

    func testOSCSequencesAreDropped() {
        XCTAssertEqual(
            ConsoleTextParser.parse("a\u{1B}]0;window title\u{07}b").map(\.text),
            ["ab"]
        )
        XCTAssertEqual(
            ConsoleTextParser.parse("a\u{1B}]8;;https://example.com\u{1B}\\b").map(\.text),
            ["ab"]
        )
    }

    func testOtherControlCharactersAreDropped() {
        XCTAssertEqual(ConsoleTextParser.parse("a\u{07}b\u{00}c").map(\.text), ["abc"])
    }

    func testTabsAreKept() {
        XCTAssertEqual(ConsoleTextParser.parse("a\tb").map(\.text), ["a\tb"])
    }

    // MARK: - \r 覆盖与多行

    func testCarriageReturnKeepsLastOverwrite() {
        XCTAssertEqual(ConsoleTextParser.lines(in: "10%\r50%\r100%"), ["100%"])
        XCTAssertEqual(ConsoleTextParser.parse("10%\r50%\r100%").map(\.text), ["100%"])
    }

    func testCRLFIsOneLineBreak() {
        XCTAssertEqual(ConsoleTextParser.lines(in: "a\r\nb\n"), ["a", "b"])
    }

    func testMultiLineChunkSplitsAndKeepsLastWithoutTrailingNewline() {
        XCTAssertEqual(ConsoleTextParser.lines(in: "a\nb\nc"), ["a", "b", "c"])
        XCTAssertEqual(ConsoleTextParser.lines(in: "a\n\nb\n"), ["a", "", "b"])
    }

    // MARK: - Minecraft `§`

    func testMinecraftColorCodes() {
        let segments = ConsoleTextParser.parse("[Server] \u{00A7}aDone\u{00A7}r!")
        XCTAssertEqual(segments, [
            ConsoleTextSegment(text: "[Server] "),
            ConsoleTextSegment(text: "Done", color: .rgb(85, 255, 85)),
            ConsoleTextSegment(text: "!"),
        ])
    }

    func testMinecraftFormattingCodes() {
        let segments = ConsoleTextParser.parse("\u{00A7}l\u{00A7}cWARN\u{00A7}r ok")
        XCTAssertEqual(segments, [
            ConsoleTextSegment(text: "WARN", color: .rgb(255, 85, 85), isBold: true),
            ConsoleTextSegment(text: " ok"),
        ])
        // 删除线/下划线/斜体/随机：渲染不出来，但码必须吃掉，别把 "§m" 留在文本里。
        XCTAssertEqual(ConsoleTextParser.parse("\u{00A7}mstruck").map(\.text), ["struck"])
    }

    func testSectionSignAtEndIsDropped() {
        XCTAssertEqual(ConsoleTextParser.parse("text\u{00A7}").map(\.text), ["text"])
    }

    // MARK: - 纯文本

    func testPlainTextStripsEverything() {
        XCTAssertEqual(
            ConsoleTextParser.plainText("\u{1B}[1;32m\u{00A7}lDone\u{1B}[0m\u{00A7}r!"),
            "Done!"
        )
    }
}
