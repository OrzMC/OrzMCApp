import Foundation
import XCTest
@testable import OrzMCLauncher

/// 控制台**按实例隔离**：四种核心 × 多个版本可以同时跑，日志/命令不能串台。
final class ServerConsoleRegistryTests: XCTestCase {
    private let paper = ConsoleInstanceKey(versionId: "1.21.5", softwareId: "Paper")
    private let vanilla = ConsoleInstanceKey(versionId: "1.21.5", softwareId: "Vanilla")
    private let otherVersion = ConsoleInstanceKey(versionId: "1.20.6", softwareId: "Fabric")

    func testKeyRoundTripsThroughRawValue() {
        XCTAssertEqual(paper.rawValue, "1.21.5#Paper")
        XCTAssertEqual(ConsoleInstanceKey(rawValue: web(paper.rawValue)), paper,
                       "要与进程登记表的键同构")
        XCTAssertNil(ConsoleInstanceKey(rawValue: "no-separator"))
    }

    private func web(_ value: String) -> String { value }

    func testEachInstanceHasItsOwnConsole() async {
        let registry = await ServerConsoleRegistry()
        let paperConsole = await MainActor.run { registry.model(for: paper) }
        let vanillaConsole = await MainActor.run { registry.model(for: vanilla) }

        await MainActor.run {
            paperConsole.append("[Paper] loading plugins\n")
            vanillaConsole.append("[Vanilla] Done (1.2s)!\n")
        }

        let paperLines = await paperConsole.lines.map(\.text)
        let vanillaLines = await vanillaConsole.lines.map(\.text)
        XCTAssertEqual(paperLines, ["[Paper] loading plugins"], "日志不能串到别的实例")
        XCTAssertEqual(vanillaLines, ["[Vanilla] Done (1.2s)!"])
        XCTAssertFalse(paperConsole === vanillaConsole, "每个实例必须是独立模型")
    }

    func testSameModelIsReusedForSameKey() async {
        let registry = await ServerConsoleRegistry()
        let first = await MainActor.run { registry.model(for: paper) }
        await MainActor.run { first.append("kept\n") }
        let second = await MainActor.run { registry.model(for: paper) }
        let lines = await second.lines.map(\.text)
        XCTAssertEqual(lines, ["kept"], "同一实例换界面再进来，历史要还在")
        XCTAssertTrue(first === second)
    }

    func testDetachKeepsLogButStopsAcceptingCommands() async {
        let registry = await ServerConsoleRegistry()
        let process = FakeEchoProcess()
        await MainActor.run { registry.attach(process, to: paper) }

        let attached = await MainActor.run { registry.isAttached(paper) }
        XCTAssertTrue(attached)

        await MainActor.run { registry.detach(paper, reason: "Server exited (code 0)") }
        let stillAttached = await MainActor.run { registry.isAttached(paper) }
        XCTAssertFalse(stillAttached)

        let model = await MainActor.run { registry.model(for: paper) }
        let lines = await model.lines.map(\.text)
        XCTAssertTrue(lines.contains { $0.contains("Server exited") }, "解绑原因要留在日志里")
    }

    func testRemoveClearsConsoleForThatInstanceOnly() async {
        let registry = await ServerConsoleRegistry()
        await MainActor.run {
            registry.model(for: paper).append("paper log\n")
            registry.model(for: otherVersion).append("fabric log\n")
        }
        await MainActor.run { registry.remove(paper) }

        let hasPaper = await MainActor.run { registry.hasConsole(for: paper) }
        let hasFabric = await MainActor.run { registry.hasConsole(for: otherVersion) }
        XCTAssertFalse(hasPaper)
        XCTAssertTrue(hasFabric, "只清被删实例，别动别的")
    }

    func testActiveKeysTrackAttachedInstances() async {
        let registry = await ServerConsoleRegistry()
        await MainActor.run {
            registry.attach(FakeEchoProcess(), to: paper)
            registry.attach(FakeEchoProcess(), to: vanilla)
        }
        let keys = await MainActor.run { Set(registry.activeKeys) }
        XCTAssertEqual(keys, [paper, vanilla])
    }
}

/// 满足 `ServerConsoleProcess` 的假进程（不真的起进程，测注册表用）。
private final class FakeEchoProcess: ServerConsoleProcess, @unchecked Sendable {
    private(set) var sent: [String] = []
    var isRunning = true
    var processIdentifier: Int32 = 4242

    func send(_ command: String) -> Bool {
        guard isRunning else { return false }
        sent.append(command)
        return true
    }
}
