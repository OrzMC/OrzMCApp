/// 远程日志的显示事实源；清空后只展示新收到的输出，ID 不复用。
public struct RemoteConsoleBuffer: Equatable, Sendable {
    public struct Line: Identifiable, Equatable, Sendable {
        public let id: UInt64
        public let text: String
    }

    public private(set) var lines: [Line] = []
    private var nextID: UInt64 = 0
    private let capacity: Int

    public init(capacity: Int = 2000) { self.capacity = max(1, capacity) }

    public mutating func append(_ text: String) {
        lines.append(Line(id: nextID, text: text))
        nextID &+= 1
        if lines.count > capacity { lines.removeFirst(lines.count - capacity) }
    }

    public mutating func clear() { lines.removeAll() }
}
