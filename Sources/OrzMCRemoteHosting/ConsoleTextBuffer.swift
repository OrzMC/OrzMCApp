//
//  ConsoleTextBuffer.swift
//  OrzMCRemoteHosting
//
//  实时流的**文本累积器**：把一条条推过来的输出片段攒成可以喂给 `ConsoleTextParser` 的整段文本，
//  并在超过上限时从**最前面按行**裁剪（不会把某行从中间切断，也不会破坏 `\r` 覆盖语义）。
//
//  为什么不用"每次重取整段"：实时流是增量推送（一段 JSON 里就几十字节），
//  整段重取的代价随会话时长线性增长；这里只追加。
//

import Foundation

public struct ConsoleTextBuffer: Sendable {

    /// 保留的字符上限（按 UTF-8 字节计，避免长会话把内存撑爆）。
    public let limit: Int
    private var storage = ""

    public init(limit: Int = 256 * 1024) {
        // 下限只防『0 字节』这种明显写错的配置；不要偷偷放大用户给的上限（单测用它验证裁剪）。
        self.limit = max(64, limit)
    }

    public var text: String { storage }

    public var isEmpty: Bool { storage.isEmpty }

    /// 追加一段输出（可能是半行，也可能没有换行）。
    public mutating func append(_ chunk: String) {
        guard !chunk.isEmpty else { return }
        storage.append(contentsOf: chunk)
        trimIfNeeded()
    }

    /// 整段替换（首次加载历史 / 用户点刷新时用）。
    public mutating func reset(to text: String) {
        storage = text
        trimIfNeeded()
    }

    public mutating func removeAll() {
        storage.removeAll()
    }

    /// 超长时从前面裁掉，**切在换行之后**：宁可多留一点，也不要把一行切成两半。
    private mutating func trimIfNeeded() {
        guard storage.utf8.count > limit else { return }
        // 目标：让尾部大约剩 limit 字节；从前向后找第一个换行作为切点。
        let excess = storage.utf8.count - limit
        let cutIndex = storage.index(storage.startIndex, offsetBy: min(excess, storage.count))
        if let newline = storage[cutIndex...].firstIndex(of: "\n") {
            storage = String(storage[storage.index(after: newline)...])
        } else {
            storage = String(storage[cutIndex...])
        }
    }
}
