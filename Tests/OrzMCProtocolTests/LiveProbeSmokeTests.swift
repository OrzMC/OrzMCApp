import XCTest

@testable import OrzMCProtocol

/// **可选的真机 smoke test**：验证真实网络路径（前面那些用例都是假流）。
///
/// 默认跳过（CI 上没有本地服务器）。本地想跑：
/// ```
/// ORZMC_LIVE_PROBE=127.0.0.1:25565 swift test --package-path swift/app --filter LiveProbe
/// ```
final class LiveProbeSmokeTests: XCTestCase {

    private var target: (host: String, port: Int32)? {
        guard let raw = ProcessInfo.processInfo.environment["ORZMC_LIVE_PROBE"] else { return nil }
        let parts = raw.split(separator: ":")
        guard parts.count == 2, let port = Int32(parts[1]) else { return nil }
        return (String(parts[0]), port)
    }

    func testLiveServerStatus() async throws {
        // 没有配置目标就跳过（CI 上没有本地服务器）。
        guard let target else {
            throw XCTSkip("set ORZMC_LIVE_PROBE=host:port to run this test")
        }
        let summary = try await MCServerProbe().status(host: target.host, port: target.port)
        XCTAssertNotNil(summary.versionName, "a live server must report its version")
        print("live probe: \(summary.versionName ?? "?") players=\(summary.playersOnline ?? -1)/\(summary.playersMax ?? -1) ping=\(summary.latencyMilliseconds)ms")
    }

    /// 真实 RCON（本地 `python3` 假服务端）：验证**多包响应**在真 socket 上也能读全。
    /// `ORZMC_LIVE_RCON=host:port:password`。
    func testLiveRCONJoinsMultiplePackets() async throws {
        guard let raw = ProcessInfo.processInfo.environment["ORZMC_LIVE_RCON"] else {
            throw XCTSkip("set ORZMC_LIVE_RCON=host:port:password to run this test")
        }
        let parts = raw.split(separator: ":")
        guard parts.count == 3, let port = Int32(parts[1]) else {
            throw XCTSkip("ORZMC_LIVE_RCON must be host:port:password")
        }
        let reply = try await MCServerProbe().runRCON(
            host: String(parts[0]),
            port: port,
            password: String(parts[2]),
            command: "list"
        )
        XCTAssertTrue(reply.contains("There are 2 of a max of 20 players online"), reply)
        XCTAssertTrue(reply.contains("alice, bob"), "第二个包也要读回来：\(reply)")
    }

    /// 黑洞地址必须**按时失败**，而不是让界面一直转圈。
    func testUnreachableServerTimesOut() async {
        let probe = MCServerProbe()
        let started = Date()
        do {
            _ = try await probe.status(host: "10.255.255.1", port: 25565, timeout: .seconds(2))
            XCTFail("should time out")
        } catch {
            let elapsed = Date().timeIntervalSince(started)
            XCTAssertLessThan(elapsed, 6, "timeout must actually fire")
        }
    }
}
