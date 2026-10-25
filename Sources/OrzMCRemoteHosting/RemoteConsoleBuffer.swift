import Foundation
import OrzMCFoundation

/// 远程日志的显示事实源；清空后只展示新收到的输出，ID 不复用。
///
/// 一条 WebSocket 消息里可能有**多行**、也可能带 ANSI / `§` 颜色码（exaroton 的控制台
/// 直接回传 Paper 的原始输出），所以这里按行拆分并调用共享解析器，
/// 与 macOS 本地控制台、自建服务器 RCON 控制台走同一套渲染（见 `docs/console-rendering.md`）。
public struct RemoteConsoleBuffer: Equatable, Sendable {
    public struct Line: Identifiable, Equatable, Sendable {
        public let id: UInt64
        /// 纯文本（已去掉控制序列；搜索/导出/无障碍读它）。
        public let text: String
        /// 解析后的分段（颜色 / 加粗），界面渲染用它。
        public let segments: [ConsoleTextSegment]

        public init(id: UInt64, text: String, segments: [ConsoleTextSegment]) {
            self.id = id
            self.text = text
            self.segments = segments
        }
    }

    /// 默认保留多少行（滚动后丢弃最旧的；服务端能刷几十万行）。
    /// 与 `ServerConsoleBuffer.defaultCapacity` 保持一致 —— 三个控制台同一个上限。
    public static let defaultCapacity = 2000

    public private(set) var lines: [Line] = []
    private var nextID: UInt64 = 0
    private let capacity: Int

    public init(capacity: Int = RemoteConsoleBuffer.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    /// 追加一条消息（可能是多行、可能带颜色码）。
    public mutating func append(_ chunk: String) {
        for raw in ConsoleTextParser.lines(in: chunk) {
            let segments = ConsoleTextParser.trimmingWhitespace(ConsoleTextParser.parse(raw))
            let text = segments.reduce(into: "") { $0 += $1.text }
            guard !text.isEmpty else { continue }
            lines.append(Line(id: nextID, text: text, segments: segments))
            nextID &+= 1
        }
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }

    public mutating func clear() { lines.removeAll() }
}
