//
//  ConsoleTextBufferTests.swift
//  OrzMCRemoteHostingTests
//
//  实时流的文本累积器：追加、整段替换、超长按行裁剪。
//  红线：裁剪**只切在换行之后**，不能把一行切成两半，也不能破坏 `\r` 覆盖语义。
//

import Testing

@testable import OrzMCRemoteHosting

@Suite("控制台文本累积器")
struct ConsoleTextBufferTests {

    @Test("追加半行片段，拼起来仍是原文")
    func appendFragments() {
        var buffer = ConsoleTextBuffer()
        buffer.append("[12:00:00] Done")
        buffer.append(" (1.2s)!\r\n")
        buffer.append("[12:00:01] [Server thread/INFO]: 世界已保存\r\n")
        #expect(buffer.text == "[12:00:00] Done (1.2s)!\r\n[12:00:01] [Server thread/INFO]: 世界已保存\r\n")
    }

    @Test("空片段不影响内容")
    func appendEmpty() {
        var buffer = ConsoleTextBuffer()
        buffer.append("abc")
        buffer.append("")
        #expect(buffer.text == "abc")
    }

    @Test("整段替换（轮询路径）")
    func reset() {
        var buffer = ConsoleTextBuffer()
        buffer.append("旧的内容\n")
        buffer.reset(to: "新的内容\n")
        #expect(buffer.text == "新的内容\n")
    }

    @Test("超过上限时从前面裁掉，且切在换行之后")
    func trimsAtLineBoundary() {
        var buffer = ConsoleTextBuffer(limit: 120)
        for index in 0..<40 {
            buffer.append("line-\(index)-padding-padding\n")
        }
        #expect(buffer.text.utf8.count <= 120 + 40, "裁剪后应回到上限附近，拿到 \(buffer.text.utf8.count)")
        #expect(buffer.text.hasPrefix("line-"), "必须从某一整行的开头开始")
        #expect(buffer.text.hasSuffix("\n"), "尾部内容不能丢")
        // 保留下来的应该是**最后**那些行。
        #expect(buffer.text.contains("line-39-"))
    }

    @Test("单行超长（没有换行）时仍然能裁，不会卡住")
    func trimsWithoutNewline() {
        var buffer = ConsoleTextBuffer(limit: 1024)
        buffer.append(String(repeating: "x", count: 5000))
        #expect(buffer.text.utf8.count <= 1024 + 1)
        #expect(!buffer.isEmpty)
    }

    @Test("`\\r` 覆盖式进度条不被裁剪破坏")
    func keepsCarriageReturns() {
        var buffer = ConsoleTextBuffer(limit: 2048)
        buffer.append("下载中 10%\r下载中 60%\r下载中 100%\n")
        // 缓冲只负责原样累积；`\r` 的覆盖语义由 `ConsoleTextParser` 处理（红线）。
        #expect(buffer.text.contains("\r"))
        #expect(buffer.text.hasSuffix("100%\n"))
    }
}
