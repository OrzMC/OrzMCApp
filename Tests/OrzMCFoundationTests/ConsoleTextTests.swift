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

    func testTerminalRedrawReplacesColoredPartialCommand() {
        // 脱敏后的真实 MCSManager 输出：终端先着色绘制 lis，再退格重绘 list。
        let raw = "> \u{1B}[31ml\u{1B}[0m\u{1B}[31mi\u{1B}[0m\u{1B}[31ms\u{1B}[0m\u{08}\u{08}\u{08}list\u{1B}[K"
        XCTAssertEqual(ConsoleTextParser.parse(raw), [ConsoleTextSegment(text: "> list")])
    }

    // MARK: - 终端重绘（真实 MCSManager 原文字节，2026-11-05）
    //
    // 面板把 PTY 输出原样返回（`> ` 提示符 + 逐字回显 + 重绘）。JLine 的逐字重绘**不只**用 `\b`：
    // 它还会用 CSI 光标左移（`ESC [ 6 D`）。以前解析器只实现了 `\b`，把 `ESC [ 6 D` 当"未知 CSI 丢弃"，
    // 于是光标没回去、同一行被写成 `> versioversion` / `> pluginplugins`（真机截图在 issue 里）。
    // 下面两条是**未做任何修改的原始字节**（只把 ESC 写成 `\u{1B}`）。

    func testRealRedrawWithCsiCursorLeftForVersion() {
        let raw = "> v\u{08}\u{1B}[31mve\u{1B}[0m\u{1B}[K\u{08}\u{08}ver\u{1B}[K\u{08}\u{08}\u{08}"
            + "\u{1B}[31mvers\u{1B}[0m\u{1B}[K\u{1B}[31mi\u{1B}[0m\u{1B}[31mo\u{1B}[0m\u{1B}[6Dversion\u{1B}[K"
        XCTAssertEqual(ConsoleTextParser.parse(raw), [ConsoleTextSegment(text: "> version")])
    }

    func testRealRedrawWithCsiCursorLeftForPlugins() {
        let raw = "> \u{1B}[31mp\u{1B}[0m\u{08}pl\u{1B}[K\u{08}\u{08}\u{1B}[31mplu\u{1B}[0m\u{1B}[K"
            + "\u{1B}[31mg\u{1B}[0m\u{1B}[31mi\u{1B}[0m\u{1B}[31mn\u{1B}[0m\u{1B}[6Dplugins\u{1B}[K"
        XCTAssertEqual(ConsoleTextParser.parse(raw), [ConsoleTextSegment(text: "> plugins")])
    }

    func testCursorMovementSequences() {
        // CUB（左移）默认 1；`ESC [ 0 D` 也按 1 算（ECMA-48）。
        XCTAssertEqual(ConsoleTextParser.plainText("abc\u{1B}[1DX"), "abX")
        XCTAssertEqual(ConsoleTextParser.plainText("abc\u{1B}[DX"), "abX")
        XCTAssertEqual(ConsoleTextParser.plainText("abc\u{1B}[0DX"), "abX")
        // 移过头不能变成负位置。
        XCTAssertEqual(ConsoleTextParser.plainText("ab\u{1B}[9DX"), "Xb")
        // CUF（右移）：超出行尾的位置用空格补齐（与真终端一致）。
        XCTAssertEqual(ConsoleTextParser.plainText("ab\u{1B}[2CX"), "ab  X")
        // CHA（回到第 n 列，1 基）。
        XCTAssertEqual(ConsoleTextParser.plainText("abcdef\u{1B}[1GX"), "Xbcdef")
        XCTAssertEqual(ConsoleTextParser.plainText("abcdef\u{1B}[3GX"), "abXdef")
        // 光标移动本身不改变颜色/加粗状态。
        XCTAssertEqual(ConsoleTextParser.parse("\u{1B}[31mab\u{1B}[1D\u{1B}[32mX"), [
            ConsoleTextSegment(text: "a", color: .red),
            ConsoleTextSegment(text: "X", color: .green),
        ])
    }

    func testCursorUpAndDownAreStillDropped() {
        // 单行渲染器没有多行光标模型：上下移不做，但不能把可见文字吞掉。
        XCTAssertEqual(ConsoleTextParser.plainText("ab\u{1B}[2Acd"), "abcd")
        XCTAssertEqual(ConsoleTextParser.plainText("ab\u{1B}[1Bcd"), "abcd")
    }

    func testRealRedrawWithExtendedCommandLine() {
        // 同一次会话里的两条长命令（原始字节）：`\e[8D` / `\e[6D` 与退格混用，
        // 还带多段颜色重绘。期望值就是维护者在终端里打的那两条命令。
        let addLine = "> w\u{08}\u{1B}[31mwh\u{1B}[0m\u{1B}[K\u{1B}[31mi\u{1B}[0m\u{1B}[31mt\u{1B}[0m\u{1B}[31me"
            + "\u{1B}[0m\u{1B}[31ml\u{1B}[0m\u{1B}[31mi\u{1B}[0m\u{1B}[31ms\u{1B}[0m\u{1B}[8Dwhitelist\u{1B}[K"
            + "\u{1B}[31m \u{1B}[0m\u{1B}[31ma\u{1B}[0m\u{1B}[31md\u{1B}[0m\u{08}\u{08}\u{08} add\u{1B}[K"
            + "\u{1B}[31m \u{1B}[0m\u{08} \u{1B}[36mP\u{1B}[0m\u{1B}[K\u{1B}[36mr\u{1B}[0m\u{1B}[36mo\u{1B}[0m"
            + "\u{1B}[36mb\u{1B}[0m\u{1B}[36me\u{1B}[0m\u{1B}[36mB\u{1B}[0m"
        XCTAssertEqual(ConsoleTextParser.plainText(addLine), "> whitelist add ProbeB")

        let removeLine = "> w\u{08}\u{1B}[31mwh\u{1B}[0m\u{1B}[K\u{1B}[31mi\u{1B}[0m\u{1B}[31mt\u{1B}[0m\u{1B}[31me"
            + "\u{1B}[0m\u{1B}[31ml\u{1B}[0m\u{1B}[31mi\u{1B}[0m\u{1B}[31ms\u{1B}[0m\u{1B}[8Dwhitelist\u{1B}[K"
            + "\u{1B}[31m \u{1B}[0m\u{1B}[31mr\u{1B}[0m\u{1B}[31me\u{1B}[0m\u{1B}[31mm\u{1B}[0m\u{1B}[31mo"
            + "\u{1B}[0m\u{1B}[31mv\u{1B}[0m\u{1B}[6D remove\u{1B}[K\u{1B}[31m \u{1B}[0m\u{08} \u{1B}[36mP"
            + "\u{1B}[0m\u{1B}[K\u{1B}[36mr\u{1B}[0m\u{1B}[36mo\u{1B}[0m\u{1B}[36mb\u{1B}[0m\u{1B}[36me"
            + "\u{1B}[0m\u{1B}[36mB\u{1B}[0m"
        XCTAssertEqual(ConsoleTextParser.plainText(removeLine), "> whitelist remove ProbeB")
    }

    func testBackspaceOverwritesWithoutErasingUntouchedSuffix() {
        XCTAssertEqual(ConsoleTextParser.plainText("abc\u{08}\u{08}X"), "aXc")
        XCTAssertEqual(ConsoleTextParser.plainText("abc\u{08}\u{08}X\u{1B}[K"), "aX")
        XCTAssertEqual(ConsoleTextParser.plainText("\u{08}a"), "a")
    }

    func testEraseLineKeepsCursorAndUnaffectedCells() {
        XCTAssertEqual(ConsoleTextParser.plainText("abc\u{08}\u{08}\u{1B}[1KX"), " Xc")
        XCTAssertEqual(ConsoleTextParser.plainText("abc\u{08}\u{08}\u{1B}[2KX"), " X ")
        XCTAssertEqual(ConsoleTextParser.parse("\u{1B}[31mab\u{08}\u{1B}[32mX"), [
            ConsoleTextSegment(text: "a", color: .red),
            ConsoleTextSegment(text: "X", color: .green),
        ])
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

    /// **回归**：行尾只有一个 `\r` 时**不能**把整行丢掉。
    ///
    /// 真实事故（0.1.4，iOS 真机）：exaroton 的 console 流每行都以 `\r` 结尾，
    /// 旧实现把"最后一个 `\r` 之后"当正文 → 空 → 整行被丢弃 → 控制台一直显示占位。
    func testTrailingCarriageReturnKeepsTheLine() {
        XCTAssertEqual(
            ConsoleTextParser.lines(in: "[20:11:02] [Server thread/INFO]: Done\r"),
            ["[20:11:02] [Server thread/INFO]: Done"]
        )
        XCTAssertEqual(
            ConsoleTextParser.parse("[20:11:02] [Server thread/INFO]: Done\r").map(\.text),
            ["[20:11:02] [Server thread/INFO]: Done"]
        )
        XCTAssertEqual(
            ConsoleTextParser.parse("\u{1B}[32mDone\u{1B}[0m\r"),
            [ConsoleTextSegment(text: "Done", color: .green)]
        )
    }

    func testTrailingCarriageReturnAfterProgressKeepsLastState() {
        XCTAssertEqual(ConsoleTextParser.lines(in: "10%\r50%\r100%\r"), ["100%"])
    }

    func testCRLFKeepsColoredLine() {
        // 行尾 `\r` 只影响行覆盖，不改变分段（颜色段照旧）。
        XCTAssertEqual(
            ConsoleTextParser.parse("\u{1B}[33mWARN\u{1B}[0m: lag\r"),
            [
                ConsoleTextSegment(text: "WARN", color: .yellow),
                ConsoleTextSegment(text: ": lag"),
            ]
        )
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
