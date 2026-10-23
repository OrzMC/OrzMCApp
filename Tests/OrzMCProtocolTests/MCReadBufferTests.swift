import XCTest

@testable import OrzMCProtocol

/// 读缓冲：TCP 一次送回来的字节数不等于我们要的字节数（真实 bug：多出来的被丢掉 → 下一个包永远读不到）。
final class MCReadBufferTests: XCTestCase {

    func testTakeReturnsRequestedPrefix() {
        var buffer = MCReadBuffer()
        buffer.append(Data([1, 2, 3, 4, 5]))
        XCTAssertEqual(buffer.take(2), Data([1, 2]))
        XCTAssertEqual(buffer.take(3), Data([3, 4, 5]))
        XCTAssertTrue(buffer.isEmpty)
    }

    /// 关键回归：一次读回 5 字节、只要 2 字节，剩下 3 字节必须留给下一次。
    func testKeepsSurplusBytesForNextRead() {
        var buffer = MCReadBuffer()
        buffer.append(Data([10, 11, 12, 13, 14]))
        XCTAssertEqual(buffer.take(1), Data([10]))
        XCTAssertEqual(buffer.take(4), Data([11, 12, 13, 14]))
    }

    func testReturnsNilWhenNotEnough() {
        var buffer = MCReadBuffer()
        buffer.append(Data([1, 2]))
        XCTAssertNil(buffer.take(3))
        buffer.append(Data([3]))
        XCTAssertEqual(buffer.take(3), Data([1, 2, 3]))
    }

    func testRemoveAllClearsStorage() {
        var buffer = MCReadBuffer()
        buffer.append(Data([1, 2, 3]))
        buffer.removeAll()
        XCTAssertTrue(buffer.isEmpty)
        XCTAssertNil(buffer.take(1))
    }
}

/// `RaceWithTimeout`：超时必须**立刻**返回，而不是等被卡住的工作收尾。
final class RaceWithTimeoutTests: XCTestCase {

    func testReturnsWorkResultWhenFastEnough() async throws {
        let value = try await RaceWithTimeout.run(timeout: .seconds(2)) { 42 }
        XCTAssertEqual(value, 42)
    }

    func testTimesOutWithoutWaitingForSlowWork() async {
        let start = Date()
        do {
            _ = try await RaceWithTimeout.run(timeout: .milliseconds(300)) {
                try await Task.sleep(for: .seconds(5))
                return 1
            }
            XCTFail("should time out")
        } catch {
            XCTAssertEqual(error as? MCProbeError, .timedOut)
            XCTAssertLessThan(Date().timeIntervalSince(start), 2.0, "timeout must not wait for the slow work")
        }
    }

    func testOnTimeoutRuns() async {
        let flag = LockedFlag()
        _ = try? await RaceWithTimeout.run(
            timeout: .milliseconds(200),
            onTimeout: { flag.set() },
            work: {
                try await Task.sleep(for: .seconds(3))
                return 0
            }
        )
        XCTAssertTrue(flag.value)
    }

    func testWorkErrorPropagates() async {
        struct Boom: Error {}
        do {
            _ = try await RaceWithTimeout.run(timeout: .seconds(2)) { throw Boom() }
            XCTFail("should throw")
        } catch {
            XCTAssertTrue(error is Boom)
        }
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    func set() { lock.lock(); storage = true; lock.unlock() }
    var value: Bool { lock.lock(); defer { lock.unlock() }; return storage }
}
