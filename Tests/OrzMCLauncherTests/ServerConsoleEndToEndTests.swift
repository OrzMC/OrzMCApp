import Foundation
import XCTest
@testable import OrzMCLauncher

/// 服务端控制台的**端到端验收**：真子进程 + 真 `send` + 真日志流（不经 GUI）。
///
/// 用一个假服务端（`sh` 循环读命令、回 MC 风格日志、`stop` 退出）走完整链路：
/// `attach` → 日志流进来（带 ANSI）→ 用户命令送到 stdin → 子进程回应 → `stop` → 退出 → `detach`。
/// 这层在 CI/air 上都能跑；真正点按钮的观感仍需人眼（见 docs）。
final class ServerConsoleEndToEndTests: XCTestCase {
    #if !os(Windows)
    /// 假服务端：读一行 → 回一行带 ANSI 的日志；`stop` → 回日志后退出。
    private static let fakeServer = """
    printf '\\033[32m[Server] Starting fake server\\033[0m\\n'
    while IFS= read -r line; do
      case "$line" in
        stop)
          printf '[Server] Stopping server\\n'
          exit 0
          ;;
        *)
          printf '[Server] %s\\n' "$line"
          ;;
      esac
    done
    """

    func testConsoleStreamsLogsAndSendsCommands() async throws {
        let console = await ServerConsoleModel()
        let process = await MainActor.run { () -> FakeServerProcess in
            let process = FakeServerProcess(script: Self.fakeServer)
            console.attach(process, label: "1.21.5 Paper")
            return process
        }
        // 把子进程输出接进控制台（真实链路就是这样接的：`ServerInfo.onServerLog`）。
        await MainActor.run { process.onLine = { chunk in console.append(chunk) } }

        // 1) 启动横幅（带 ANSI）：颜色码必须被剥掉
        try await waitUntil { await console.lines.contains { $0.text.contains("Starting fake server") } }
        let banner = await console.lines.first { $0.text.contains("Starting fake server") }
        XCTAssertFalse(banner?.text.contains("\u{1B}") ?? true, "ANSI 必须被剥掉")

        // 2) 用户命令 → 子进程 stdin → 回应出现在控制台
        let sent = await MainActor.run { console.send("say hello") }
        XCTAssertTrue(sent)
        try await waitUntil { await console.lines.contains { $0.text.contains("[Server] say hello") } }

        // 3) 命令回显带 isCommand 标记（UI 用强调色区分日志与输入）
        let echoed = await console.lines.last { $0.isCommand }
        XCTAssertEqual(echoed?.text, "say hello")

        // 4) `stop` 让假服务端退出（子进程退出码 0）
        _ = await MainActor.run { console.send("stop") }
        let code = await process.waitForExit()
        XCTAssertEqual(code, 0)

        // 5) 解绑后不能再"假装发送成功"
        await MainActor.run { console.detach(reason: "Server exited") }
        let attached = await console.isAttached
        XCTAssertFalse(attached)
        let stillOk = await MainActor.run { console.send("say after exit") }
        XCTAssertFalse(stillOk)
    }

    func testSendWithoutServerIsRejected() async {
        let console = await ServerConsoleModel()
        let ok = await MainActor.run { console.send("say hi") }
        XCTAssertFalse(ok, "没挂进程时不能假装发送成功")
        let warned = await console.lines.contains { $0.text.contains("not running") }
        XCTAssertTrue(warned)
    }

    func testPartialLineIsFlushedOnDetach() async {
        let console = await ServerConsoleModel()
        await MainActor.run { console.append("half a line") }
        await MainActor.run { console.detach() }
        let flushed = await console.lines.contains { $0.text == "half a line" }
        XCTAssertTrue(flushed, "解绑时要把残留半行输出，别丢最后一行")
    }

    /// 轮询等待（异步日志流没有"完成"信号，只能等）。
    private func waitUntil(
        timeout: TimeInterval = 5,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () async -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("等待超时", file: file, line: line)
    }
    #endif
}

#if !os(Windows)
/// 假服务端进程：只实现控制台需要的三件事（`isRunning` / `processIdentifier` / `send`）。
final class FakeServerProcess: ServerConsoleProcess, @unchecked Sendable {
    /// 输出回调（测试里指到 `console.append`，真实链路指到 `ServerInfo.onServerLog`）。
    var onLine: (@Sendable (String) -> Void)?

    private let handle: Process
    private let stdin: FileHandle

    init(script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]

        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = output
        let box = CallbackBox()
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            box.sink?(text)
        }
        try? process.run()
        handle = process
        stdin = input.fileHandleForWriting
        box.sink = { [weak self] text in self?.onLine?(text) }
    }

    var isRunning: Bool { handle.isRunning }
    var processIdentifier: Int32 { handle.processIdentifier }

    func send(_ command: String) -> Bool {
        guard handle.isRunning else { return false }
        let line = command.hasSuffix("\n") ? command : command + "\n"
        return (try? stdin.write(contentsOf: Data(line.utf8))) != nil
    }

    func waitForExit() async -> Int32 {
        await withCheckedContinuation { continuation in
            handle.terminationHandler = { finished in
                continuation.resume(returning: finished.terminationStatus)
            }
        }
    }
}

/// 回调转发（`readabilityHandler` 是 `@Sendable`，这里用只读转发避免捕获可变状态）。
final class CallbackBox: @unchecked Sendable {
    var sink: (@Sendable (String) -> Void)?
}
#endif
