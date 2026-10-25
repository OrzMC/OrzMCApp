import Foundation

/// 终端文本里的一种颜色（ANSI / Minecraft 都归一到这里）。
///
/// 只保留**名字**，不掺任何 UI 值：颜色到具体 `Color` 的映射在 `OrzMCDesignSystem`
/// （`ConsoleLineText`），这样解析层可以给 CLI、单测、macOS/iOS 共用，也方便按亮/暗模式调色。
public enum ConsoleColor: Hashable, Sendable {
    case black, red, green, yellow, blue, magenta, cyan, white
    case brightBlack, brightRed, brightGreen, brightYellow
    case brightBlue, brightMagenta, brightCyan, brightWhite
    /// 真彩色（`38;2;r;g;b`、256 色 `38;5;n`、Minecraft 的 `§0`–`§f`）。
    case rgb(UInt8, UInt8, UInt8)
}

/// 一段**同样式**的文本。
public struct ConsoleTextSegment: Hashable, Sendable {
    public var text: String
    public var color: ConsoleColor?
    public var isBold: Bool

    public init(text: String, color: ConsoleColor? = nil, isBold: Bool = false) {
        self.text = text
        self.color = color
        self.isBold = isBold
    }
}

/// 控制台文本解析：把**带颜色码的原始输出**拆成「分段 + 样式」，并丢掉所有控制字符。
///
/// 支持两种颜色码（真实日志两种都会出现）：
///
/// | 来源 | 形态 | 例子 |
/// |---|---|---|
/// | ANSI SGR | `ESC [ 参数 m` | `\u{1B}[32mINFO\u{1B}[0m` |
/// | Minecraft | `§` + 1 个字符 | `§aINFO`、`§cERROR` |
///
/// 处理规则（见 `docs/console-rendering.md`）：
/// - SGR：`0` 重置、`1` 加粗、`22` 取消加粗、`30–37` / `90–97` 前景色、`39` 默认前景色、
///   `38;5;n` / `38;2;r;g;b` 扩展色；**背景色与其余 SGR 参数忽略**；
/// - **其余所有转义序列直接丢弃**（非 `m` 的 CSI、OSC、两字节 ESC），绝不把 `\u{1B}` 漏到界面；
/// - `\r`：同一行内后写的覆盖前面的（进度条），见 `lines(in:)`；
/// - 畸形/被截断的序列按「丢弃控制符、保留可见文本」处理。
///
/// 实现说明：全部按 **Unicode 标量**遍历，而不是 `Character` ——
/// Swift 会把 `"\r\n"` 当成**一个** Character，按字符比较会漏掉这个换行（实测踩过）。
public enum ConsoleTextParser {

    /// 解析**单行**文本（不处理 `\n`；`\r` 取最后一次覆盖后的内容）。
    public static func parse(_ line: String) -> [ConsoleTextSegment] {
        var scalars = Array(line.unicodeScalars)
        if let lastCarriageReturn = scalars.lastIndex(of: "\r") {
            scalars = Array(scalars[scalars.index(after: lastCarriageReturn)...])
            if scalars.first == "\n" { scalars.removeFirst() }
        }
        guard !scalars.isEmpty else { return [] }

        var segments: [ConsoleTextSegment] = []
        var buffer = ""
        var color: ConsoleColor?
        var isBold = false

        func flush() {
            guard !buffer.isEmpty else { return }
            segments.append(ConsoleTextSegment(text: buffer, color: color, isBold: isBold))
            buffer.removeAll(keepingCapacity: true)
        }

        var index = 0
        while index < scalars.count {
            let scalar = scalars[index]
            if scalar == "\u{1B}" {
                let next = index + 1
                guard next < scalars.count else { break }          // 结尾被截断的 ESC：丢掉
                if scalars[next] == "[" {
                    // CSI：参数… 终止字节（0x40…0x7E）
                    var cursor = next + 1
                    var parameters = ""
                    while cursor < scalars.count, !isFinalByte(scalars[cursor]) {
                        parameters.unicodeScalars.append(scalars[cursor])
                        cursor += 1
                    }
                    if cursor < scalars.count, scalars[cursor] == "m" {
                        // 只有 SGR 会改样式；其它 CSI（清行、光标）跳过去就行。
                        flush()
                        applySGR(parameters, color: &color, isBold: &isBold)
                    }
                    index = cursor + 1
                    continue
                }
                if scalars[next] == "]" {
                    // OSC：一直到 BEL 或 ESC \ 为止（窗口标题、超链接）。
                    var cursor = next + 1
                    while cursor < scalars.count {
                        if scalars[cursor] == "\u{07}" { cursor += 1; break }
                        if scalars[cursor] == "\u{1B}", cursor + 1 < scalars.count,
                           scalars[cursor + 1] == "\\" {
                            cursor += 2
                            break
                        }
                        cursor += 1
                    }
                    index = cursor
                    continue
                }
                index = next + 1                                     // 其它两字节 ESC（如 ESC ( B）
                continue
            }

            if scalar == "\u{00A7}" {                                // §
                let next = index + 1
                guard next < scalars.count else { break }
                flush()
                applyMinecraft(scalars[next], color: &color, isBold: &isBold)
                index = next + 1
                continue
            }

            if isConsoleControl(scalar) { index += 1; continue }      // 其余控制字符（保留 \t）
            buffer.unicodeScalars.append(scalar)
            index += 1
        }
        flush()
        return segments
    }

    /// 解析成**纯文本**（等同把各段拼起来；给"只要文本"的场景用，如日志导出）。
    public static func plainText(_ line: String) -> String {
        parse(line).reduce(into: "") { $0 += $1.text }
    }

    /// 把一段原始输出（可能是多行、可能带 `\r` 覆盖）拆成若干**已归一**的行。
    ///
    /// `\r` 语义：同一逻辑行里后写的覆盖前面的（`10%\r50%\r100%` → `100%`）；
    /// `\r\n` 视为一个换行。末尾换行不产生额外空行。
    public static func lines(in chunk: String) -> [String] {
        guard !chunk.isEmpty else { return [] }
        let scalars = chunk.unicodeScalars
        var result: [String] = []
        var current = String.UnicodeScalarView()
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "\r" {
                let next = scalars.index(after: index)
                if next < scalars.endIndex, scalars[next] == "\n" {
                    result.append(String(current))       // `\r\n` = 一个换行
                    index = scalars.index(after: next)
                } else {
                    // 单独 `\r` = 行内覆盖：前半行作废，后面才是这一行的最新状态。
                    index = next
                }
                current = String.UnicodeScalarView()
                continue
            }
            if scalar == "\n" {
                result.append(String(current))
                current = String.UnicodeScalarView()
                index = scalars.index(after: index)
                continue
            }
            current.append(scalar)
            index = scalars.index(after: index)
        }
        if !current.isEmpty { result.append(String(current)) }
        return result
    }

    /// 去掉首尾纯空白（各控制台存行时都会 trim 一次；放在这里保证 `text` 与 `segments` 一致）。
    public static func trimmingWhitespace(_ segments: [ConsoleTextSegment]) -> [ConsoleTextSegment] {
        var result = segments
        while let first = result.first, first.text.allSatisfy(\.isWhitespace) {
            result.removeFirst()
        }
        while let last = result.last, last.text.allSatisfy(\.isWhitespace) {
            result.removeLast()
        }
        if !result.isEmpty {
            result[0].text = trimLeadingWhitespace(result[0].text)
            let lastIndex = result.count - 1
            result[lastIndex].text = trimTrailingWhitespace(result[lastIndex].text)
        }
        return result.filter { !$0.text.isEmpty }
    }

    private static func trimLeadingWhitespace(_ text: String) -> String {
        guard let firstNonSpace = text.firstIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(text[firstNonSpace...])
    }

    private static func trimTrailingWhitespace(_ text: String) -> String {
        guard let lastNonSpace = text.lastIndex(where: { !$0.isWhitespace }) else { return "" }
        return String(text[...lastNonSpace])
    }

    // MARK: - SGR

    /// 应用一条 SGR（`ESC [ <parameters> m`）。参数缺省（空串）= `0`。
    private static func applySGR(
        _ parameters: String,
        color: inout ConsoleColor?,
        isBold: inout Bool
    ) {
        let raw = parameters.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) ?? 0 }
        let codes = raw.isEmpty ? [0] : raw
        var index = 0
        while index < codes.count {
            let code = codes[index]
            switch code {
            case 0:
                color = nil
                isBold = false
            case 1:
                isBold = true
            case 22:
                isBold = false
            case 30...37:
                color = basicColor(code - 30)
            case 39:
                color = nil
            case 90...97:
                color = basicColor(code - 90, bright: true)
            case 38:
                // 扩展色：38;5;n（256 色）或 38;2;r;g;b（真彩色）。参数不够就当没写。
                if let (value, consumed) = extendedColor(codes, from: index + 1) {
                    color = value
                    index += consumed
                }
            case 48:
                // 背景色：界面不用，但要把参数吃掉，免得被当成前景色解析。
                if let (_, consumed) = extendedColor(codes, from: index + 1) {
                    index += consumed
                }
            default:
                break
            }
            index += 1
        }
    }

    private static func basicColor(_ offset: Int, bright: Bool = false) -> ConsoleColor {
        let base: [ConsoleColor] = [.black, .red, .green, .yellow, .blue, .magenta, .cyan, .white]
        let brightPalette: [ConsoleColor] = [
            .brightBlack, .brightRed, .brightGreen, .brightYellow,
            .brightBlue, .brightMagenta, .brightCyan, .brightWhite,
        ]
        let palette = bright ? brightPalette : base
        guard offset >= 0, offset < palette.count else { return .white }
        return palette[offset]
    }

    /// `start` 指向扩展色的模式位（`5` 或 `2`）。返回颜色与**额外消耗**的参数个数。
    private static func extendedColor(
        _ codes: [Int],
        from start: Int
    ) -> (ConsoleColor, Int)? {
        guard start < codes.count else { return nil }
        switch codes[start] {
        case 5:
            guard start + 1 < codes.count else { return nil }
            return (xterm256(codes[start + 1]), 2)
        case 2:
            guard start + 3 < codes.count else { return nil }
            let r = UInt8(clamping: codes[start + 1])
            let g = UInt8(clamping: codes[start + 2])
            let b = UInt8(clamping: codes[start + 3])
            return (.rgb(r, g, b), 4)
        default:
            return nil
        }
    }

    /// xterm 256 色 → 颜色（16 基础色 + 6×6×6 立方 + 24 级灰阶）。
    static func xterm256(_ index: Int) -> ConsoleColor {
        let clamped = min(max(index, 0), 255)
        switch clamped {
        case 0..<16:
            let standard: [ConsoleColor] = [
                .black, .red, .green, .yellow, .blue, .magenta, .cyan, .white,
                .brightBlack, .brightRed, .brightGreen, .brightYellow,
                .brightBlue, .brightMagenta, .brightCyan, .brightWhite,
            ]
            return standard[clamped]
        case 16..<232:
            let value = clamped - 16
            let steps: [UInt8] = [0, 95, 135, 175, 215, 255]
            return .rgb(steps[value / 36], steps[(value / 6) % 6], steps[value % 6])
        default:
            let level = UInt8(8 + (clamped - 232) * 10)
            return .rgb(level, level, level)
        }
    }

    // MARK: - Minecraft `§`

    /// 处理 `§x`：颜色/加粗/重置都吃掉；不渲染的样式码（删除线等）也一律吃掉。
    private static func applyMinecraft(
        _ code: UnicodeScalar,
        color: inout ConsoleColor?,
        isBold: inout Bool
    ) {
        switch code {
        case "0": color = .rgb(0, 0, 0)
        case "1": color = .rgb(0, 0, 170)
        case "2": color = .rgb(0, 170, 0)
        case "3": color = .rgb(0, 170, 170)
        case "4": color = .rgb(170, 0, 0)
        case "5": color = .rgb(170, 0, 170)
        case "6": color = .rgb(255, 170, 0)
        case "7": color = .rgb(170, 170, 170)
        case "8": color = .rgb(85, 85, 85)
        case "9": color = .rgb(85, 85, 255)
        case "a", "A": color = .rgb(85, 255, 85)
        case "b", "B": color = .rgb(85, 255, 255)
        case "c", "C": color = .rgb(255, 85, 85)
        case "d", "D": color = .rgb(255, 85, 255)
        case "e", "E": color = .rgb(255, 255, 85)
        case "f", "F": color = .rgb(255, 255, 255)
        case "l", "L": isBold = true
        case "r", "R":
            color = nil
            isBold = false
        default:
            // k(随机) / m(删除线) / n(下划线) / o(斜体)：样式不渲染，但**码要吃掉**。
            break
        }
    }

    // MARK: - 字符判定

    /// CSI 的终止字节：`0x40…0x7E`；之前的都是参数/中间字节。
    private static func isFinalByte(_ scalar: UnicodeScalar) -> Bool {
        scalar.value >= 0x40 && scalar.value <= 0x7E
    }

    /// 需要从控制台文本里丢掉的字符（保留 `\t`：缩进有意义）。
    private static func isConsoleControl(_ scalar: UnicodeScalar) -> Bool {
        (scalar.value < 0x20 && scalar.value != 0x09) || scalar.value == 0x7F
    }
}
