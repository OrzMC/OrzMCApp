import Foundation
import OrzMCFoundation

/// Incremental display rows backed by the existing bounded raw-text buffer.
public struct ConsoleLineBuffer: Sendable {
    public struct Line: Identifiable, Equatable, Sendable {
        public let id: UInt64
        public let text: String
    }

    private var raw: ConsoleTextBuffer
    private var completed: [Line] = []
    private var pending = ""
    private var pendingID: UInt64?
    private var nextID: UInt64 = 0
    public private(set) var lines: [Line] = []

    public init(limit: Int = 256 * 1024) {
        raw = ConsoleTextBuffer(limit: limit)
    }

    public mutating func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        let removed = raw.appendReportingTrim(chunk)
        consume(chunk)
        if !removed.isEmpty {
            if removed.unicodeScalars.last == "\n" {
                let removedLines = removed.unicodeScalars.reduce(into: 0) { count, scalar in
                    if scalar == "\n" { count += 1 }
                }
                completed.removeFirst(min(removedLines, completed.count))
            } else {
                rebuild(raw.text)
            }
        }
        publishLines()
    }

    public mutating func reset(to text: String) {
        raw.reset(to: text)
        rebuild(raw.text)
        publishLines()
    }

    private mutating func allocateID() -> UInt64 {
        defer { nextID &+= 1 }
        return nextID
    }

    private mutating func consume(_ chunk: String) {
        let parts = chunk.unicodeScalars.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, part) in parts.enumerated() {
            pending.append(contentsOf: String(part))
            if index < parts.count - 1 {
                let text = ConsoleTextParser.lines(in: pending + "\n").first ?? ""
                let id = pendingID ?? allocateID()
                completed.append(Line(id: id, text: text))
                pending = ""
                pendingID = nil
            }
        }
    }

    private mutating func rebuild(_ text: String) {
        completed.removeAll(keepingCapacity: true)
        pending = ""
        pendingID = nil
        consume(text)
    }

    private mutating func publishLines() {
        lines = completed
        if let text = ConsoleTextParser.lines(in: pending).first {
            if pendingID == nil { pendingID = allocateID() }
            if let id = pendingID { lines.append(Line(id: id, text: text)) }
        }
    }
}
