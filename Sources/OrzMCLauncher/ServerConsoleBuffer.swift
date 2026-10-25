import Foundation
import OrzMCFoundation

/// 服务端控制台的一行（已分好行、已解析颜色）。
public struct ConsoleLine: Identifiable, Equatable, Sendable {
    public let id: Int
    /// 纯文本（去掉了所有控制序列；导出日志、搜索都用它）。
    public let text: String
    /// 解析后的分段（颜色 / 加粗），界面渲染用它。
    public let segments: [ConsoleTextSegment]
    /// 是否用户自己发出的命令行（在 UI 里以不同样式显示，便于和日志区分）。
    public let isCommand: Bool

    public init(id: Int, text: String, isCommand: Bool = false) {
        self.init(
            id: id,
            text: text,
            segments: ConsoleTextParser.parse(text),
            isCommand: isCommand
        )
    }

    /// 已经解析好分段时用它（避免重复解析）。
    public init(id: Int, text: String, segments: [ConsoleTextSegment], isCommand: Bool = false) {
        self.id = id
        self.text = text
        self.segments = segments
        self.isCommand = isCommand
    }
}

/// 服务端控制台的**缓冲与输入解析**（纯逻辑，可单测）。
///
/// 为什么不直接在视图里拼字符串：服务端输出是**字节块**（一次回调可能是半行，也可能一次十行），
/// 还带 ANSI 颜色码（`\u{1B}[32m`）。这些都要在模型里处理干净，视图只渲染成品。
public struct ServerConsoleBuffer: Equatable, Sendable {
    /// 最多保留多少行（滚动后丢弃最旧的；服务端能刷几十万行）。
    public static let defaultCapacity = 2000
    /// 命令历史最多保留多少条。
    public static let defaultHistoryLimit = 100

    public private(set) var lines: [ConsoleLine] = []
    public private(set) var history: [String] = []

    private let capacity: Int
    private let historyLimit: Int
    private var nextId = 0
    /// 上一次回调剩下的半行（等服务端把这一行写完）。
    private var partial = ""

    public init(capacity: Int = ServerConsoleBuffer.defaultCapacity,
                historyLimit: Int = ServerConsoleBuffer.defaultHistoryLimit) {
        self.capacity = max(capacity, 1)
        self.historyLimit = max(historyLimit, 0)
    }

    // MARK: 输出

    /// 喂入一段原始输出（可能是半行/多行）。
    ///
    /// 只按 `\n` 切；`\r` 视为行内回车（服务端进度条用）→ 丢弃当前半行，保留最后内容。
    public mutating func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        // **不在这里剥 ANSI**：颜色要留到 `push` 里解析成 `segments`。
        // 颜色码里不会有 `\n` / `\r`，所以直接按行切是安全的。
        partial += chunk

        while let breakIndex = partial.firstIndex(where: { $0 == "\n" || $0 == "\r" }) {
            let line = String(partial[partial.startIndex..<breakIndex])
            let isCarriageReturn = partial[breakIndex] == "\r"
            partial.removeSubrange(partial.startIndex...breakIndex)
            if isCarriageReturn {
                // 进度条自刷新：`\r` 之后的内容会覆盖这一行，所以这里**丢掉**前半行，
                // 只保留后续内容（真正的那一行会在下一个 `\n` 落定）。
                _ = line
            } else {
                push(line)
            }
        }
    }

    /// 把残留半行也输出（停止服务端时用，避免最后一行丢失）。
    public mutating func flush() {
        guard !partial.isEmpty else { return }
        let line = partial
        partial = ""
        push(line)
    }

    public mutating func clear() {
        lines.removeAll()
        partial = ""
    }

    private mutating func push(_ raw: String) {
        let segments = ConsoleTextParser.trimmingWhitespace(ConsoleTextParser.parse(raw))
        let text = segments.reduce(into: "") { $0 += $1.text }
        guard !text.isEmpty else { return }
        lines.append(ConsoleLine(id: nextId, text: text, segments: segments))
        nextId += 1
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
    }

    // MARK: 输入

    /// 用户按下回车：记进历史并回显一行 `> 命令`，返回要送给服务端的命令（空白 → `nil`）。
    public mutating func submitCommand(_ raw: String) -> String? {
        let command = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !command.isEmpty else { return nil }

        if history.last != command {
            history.append(command)
            if history.count > historyLimit {
                history.removeFirst(history.count - historyLimit)
            }
        }

        lines.append(ConsoleLine(
            id: nextId,
            text: command,
            segments: [ConsoleTextSegment(text: command)],
            isCommand: true
        ))
        nextId += 1
        if lines.count > capacity {
            lines.removeFirst(lines.count - capacity)
        }
        return command
    }

    /// 历史里的上一条/下一条（`index` 从末尾数；越界返回 `nil`）。
    public func historyEntry(at offset: Int) -> String? {
        guard offset >= 0, offset < history.count else { return nil }
        return history[history.count - 1 - offset]
    }

    // MARK: ANSI

    /// 去掉 ANSI 转义序列（颜色/光标控制）。服务端日志全是 `\u{1B}[32m…`。
    ///
    /// 具体规则在 `OrzMCFoundation.ConsoleTextParser`（三种控制台共用同一套解析），
    /// 这里保留旧名字以便调用方/测试平滑迁移。
    public static func strippingANSI(_ text: String) -> String {
        ConsoleTextParser.plainText(text)
    }

}
