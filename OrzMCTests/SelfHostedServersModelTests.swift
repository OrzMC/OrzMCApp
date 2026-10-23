import Foundation
import OrzMCLauncher
import OrzMCProtocol
import XCTest

@testable import OrzMC

/// 自建服务器模型：**玩家名单**（在线 / 白名单 / 封禁）与玩家操作的整合测试。
///
/// 不碰网络也不碰 Keychain：RCON 用可注入的假字节流，密码用注入的 provider。
@MainActor
final class SelfHostedServersModelTests: XCTestCase {

    // MARK: - 假 RCON 服务端（每次连接按脚本回答）

    /// 每条命令一个新连接；按 `replies` 顺序取答案（写成"服务端会发的字节"）。
    final class ScriptedStream: MCByteStream, @unchecked Sendable {
        private var incoming: [UInt8]
        private(set) var written = Data()

        init(incoming: [UInt8]) { self.incoming = incoming }

        func connect(host: String, port: Int32) throws {}
        func write(_ data: Data) throws { written.append(data) }

        func read(count: Int) throws -> Data {
            guard incoming.count >= count else { throw MCStreamError.connectionClosed }
            let slice = Array(incoming.prefix(count))
            incoming.removeFirst(count)
            return Data(slice)
        }

        func hasPendingInput(timeoutMilliseconds: Int) throws -> Bool { !incoming.isEmpty }
        func close() {}
    }

    /// `@Sendable` 的 stream factory 不能捕获可变 `var`，用锁保护一个小队列。
    final class ReplyQueue: @unchecked Sendable {
        private let lock = NSLock()
        private var replies: [[String]]

        init(_ replies: [[String]]) { self.replies = replies }

        func next() -> [String] {
            lock.lock()
            defer { lock.unlock() }
            return replies.isEmpty ? [] : replies.removeFirst()
        }
    }

    /// 一条命令的完整应答：auth 成功包 + N 个响应包。
    nonisolated private static func rconReply(_ lines: [String]) -> [UInt8] {
        var bytes = rconPacket(id: 1, type: 2, body: "")
        for line in lines {
            bytes += rconPacket(id: 2, type: 0, body: line)
        }
        return bytes
    }

    nonisolated private static func rconPacket(id: Int32, type: Int32, body: String) -> [UInt8] {
        var payload = [UInt8]()
        payload += withUnsafeBytes(of: id.littleEndian) { Array($0) }
        payload += withUnsafeBytes(of: type.littleEndian) { Array($0) }
        payload += Array(body.utf8)
        payload += [0x00, 0x00]
        var bytes = withUnsafeBytes(of: Int32(payload.count).littleEndian) { Array($0) }
        bytes += payload
        return bytes
    }

    private func makeModel(
        replies: [[String]],
        password: String? = "testpass",
        profile: SelfHostedServerProfile = SelfHostedServerProfile(
            name: "测试服", host: "127.0.0.1", port: 25565, rconPort: 25575, rconEnabled: true
        )
    ) -> (model: SelfHostedServersModel, defaults: UserDefaults) {
        let suite = "SelfHostedServersModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let queue = ReplyQueue(replies)
        let probe = MCServerProbe(streamFactory: {
            ScriptedStream(incoming: Self.rconReply(queue.next()))
        })

        var profiles = SelfHostedProfiles()
        profiles.upsert(profile)
        SelfHostedProfilesStore.save(profiles, defaults: defaults)

        let model = SelfHostedServersModel(
            probe: probe,
            defaults: defaults,
            passwordProvider: { _ in password }
        )
        return (model, defaults)
    }

    // MARK: - 名单

    func testRefreshPlayerListsParsesAllThreeLists() async {
        let (model, _) = makeModel(replies: [
            ["There are 2 of a max of 20 players online: alice, bob"],
            ["There are 1 whitelisted player(s): carol"],
            ["There are 1 ban(s):\ndave (griefing)"],
        ])

        await model.refreshPlayerLists()

        XCTAssertEqual(model.currentLists.online, ["alice", "bob"])
        XCTAssertEqual(model.currentLists.whitelisted, ["carol"])
        XCTAssertEqual(model.currentLists.banned.map(\.name), ["dave"])
        XCTAssertEqual(model.currentLists.banned.first?.reason, "griefing")
        XCTAssertNil(model.currentListError)
    }

    func testRefreshPlayerListsWithoutPasswordReportsError() async {
        let (model, _) = makeModel(replies: [], password: nil)
        await model.refreshPlayerLists()
        XCTAssertFalse(model.canRunCommands)
        // 没密码时直接跳过（不产生错误、也不去连）
        XCTAssertNil(model.currentListError)
        XCTAssertEqual(model.currentLists.online, [])
    }

    // MARK: - 玩家操作

    func testPlayerActionSendsCommandAndRefreshesLists() async {
        let (model, _) = makeModel(replies: [
            ["ok: kick alice"],                       // performPlayerAction → kick
            ["There are 2 of a max of 20 players online: bob"],   // 刷新：list
            ["There are 0 whitelisted player(s):"],               // 刷新：whitelist
            ["There are 0 ban(s):"],                              // 刷新：banlist
        ])

        await model.performPlayerAction("kick alice")

        XCTAssertEqual(model.currentLists.online, ["bob"], "动作后名单要重新拉一遍")
        XCTAssertEqual(model.currentConsoleLines.first?.kind, .command)
        XCTAssertEqual(model.currentConsoleLines.first?.text, "> kick alice")
    }

    func testSelectedProfileDefaultsToFirst() {
        let (model, _) = makeModel(replies: [])
        XCTAssertEqual(model.selected?.name, "测试服")
        XCTAssertTrue(model.profiles.servers.count == 1)
    }
}
