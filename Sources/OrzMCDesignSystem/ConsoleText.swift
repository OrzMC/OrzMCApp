import OrzMCFoundation
import SwiftUI

/// 终端颜色 → 界面颜色。
///
/// 为什么不用系统原色：控制台面板的底色是「`.primary` 6%」，浅色模式下接近白、深色模式下接近黑。
/// 直接套 `.red` / `.yellow` / ANSI 的纯色会出现两个典型问题：
/// - 深色模式下发黑（ANSI `30` 黑、`§0`）—— 看不见；
/// - 浅色模式下发白（ANSI `97` 亮白、`§f`）—— 也看不见。
///
/// 所以命名色用**中间明度**的固定色（两种模式都读得清），黑/白两族按 `ColorScheme` 取
/// "对比色"，真彩色按亮度做温和的提亮/压暗（保留色相）。
public enum ConsolePalette {

    public static func color(for color: ConsoleColor, scheme: ColorScheme) -> Color {
        switch color {
        case .black:
            return scheme == .dark ? Color(white: 0.78) : Color(white: 0.16)
        case .brightBlack:
            return Color(white: 0.5)
        case .white:
            return scheme == .dark ? Color(white: 0.92) : Color(white: 0.22)
        case .brightWhite:
            return scheme == .dark ? Color(white: 1.0) : Color(white: 0.12)
        case .red:
            return Color(.sRGB, red: 0.78, green: 0.18, blue: 0.18)
        case .brightRed:
            return Color(.sRGB, red: 0.91, green: 0.35, blue: 0.35)
        case .green:
            return Color(.sRGB, red: 0.13, green: 0.55, blue: 0.24)
        case .brightGreen:
            return Color(.sRGB, red: 0.29, green: 0.72, blue: 0.35)
        case .yellow:
            // ANSI 黄在浅色底上几乎不可读，压成琥珀色；WARN 行就靠它。
            return Color(.sRGB, red: 0.68, green: 0.47, blue: 0.03)
        case .brightYellow:
            return Color(.sRGB, red: 0.83, green: 0.63, blue: 0.10)
        case .blue:
            return Color(.sRGB, red: 0.13, green: 0.38, blue: 0.78)
        case .brightBlue:
            return Color(.sRGB, red: 0.35, green: 0.56, blue: 0.92)
        case .magenta:
            return Color(.sRGB, red: 0.60, green: 0.20, blue: 0.70)
        case .brightMagenta:
            return Color(.sRGB, red: 0.76, green: 0.36, blue: 0.85)
        case .cyan:
            return Color(.sRGB, red: 0.05, green: 0.52, blue: 0.58)
        case .brightCyan:
            return Color(.sRGB, red: 0.25, green: 0.71, blue: 0.78)
        case .rgb(let red, let green, let blue):
            return adjusted(red: red, green: green, blue: blue, scheme: scheme)
        }
    }

    /// 真彩色：浅色模式下把过亮的颜色压暗、深色模式下把过暗的颜色提亮（保留色相）。
    private static func adjusted(red: UInt8, green: UInt8, blue: UInt8, scheme: ColorScheme) -> Color {
        var (r, g, b) = (Double(red) / 255, Double(green) / 255, Double(blue) / 255)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        if scheme == .light, luminance > 0.72 {
            // 往黑里拉，最低到原色的 45%（白字 → 深灰，仍偏冷/偏暖）。
            let factor = max(0.45, 0.72 / max(luminance, 0.01))
            r *= factor
            g *= factor
            b *= factor
        } else if scheme == .dark, luminance < 0.16 {
            // 往白里抬，最高到 0.45 左右（黑字 → 中灰）。
            let lift = 0.45 - luminance
            r = min(1, r + lift)
            g = min(1, g + lift)
            b = min(1, b + lift)
        }
        return Color(.sRGB, red: r, green: g, blue: b)
    }
}

/// 把解析好的分段拼成 `AttributedString`（颜色 + 加粗），供 `ConsoleLineText` 使用。
public enum ConsoleAttributedText {

    /// - Parameter fallback: 没有颜色信息的段用这个颜色（例如本地回显的命令行）。
    public static func make(
        _ segments: [ConsoleTextSegment],
        scheme: ColorScheme,
        fallback: Color = .primary
    ) -> AttributedString {
        var result = AttributedString()
        for segment in segments {
            guard !segment.text.isEmpty else { continue }
            var piece = AttributedString(segment.text)
            piece.foregroundColor = segment.color.map { ConsolePalette.color(for: $0, scheme: scheme) } ?? fallback
            if segment.isBold {
                piece.inlinePresentationIntent = .stronglyEmphasized
            }
            result += piece
        }
        return result
    }
}

/// 控制台里的一行文本：等宽字体 + ANSI/`§` 颜色。
///
/// 三种控制台（macOS 本地服务端、自建服务器 RCON、exaroton）**共用**这一个渲染入口，
/// 解析在 `OrzMCFoundation.ConsoleTextParser`（纯逻辑、有单测），这里只负责颜色与排版。
public struct ConsoleLineText: View {

    @Environment(\.colorScheme) private var colorScheme

    private let segments: [ConsoleTextSegment]
    private let fallback: Color?
    private let font: Font

    /// - Parameters:
    ///   - segments: 解析后的分段（见 `ConsoleTextParser`）。
    ///   - fallback: 无色段的默认颜色；`nil` = `.primary`。
    ///   - font: 默认等宽（`OrzMCTheme.Typography.console`）。
    public init(
        segments: [ConsoleTextSegment],
        fallback: Color? = nil,
        font: Font = OrzMCTheme.Typography.console
    ) {
        self.segments = segments
        self.fallback = fallback
        self.font = font
    }

    /// 便捷入口：给一段**已经解析过**的纯文本（例如本地回显的命令）。
    public init(
        text: String,
        color: Color? = nil,
        font: Font = OrzMCTheme.Typography.console
    ) {
        self.init(segments: [ConsoleTextSegment(text: text)], fallback: color, font: font)
    }

    public var body: some View {
        Text(ConsoleAttributedText.make(segments, scheme: colorScheme, fallback: fallback ?? .primary))
            .font(font)
    }
}
