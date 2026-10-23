import XCTest

@testable import OrzMCLauncher

/// RCON 的"人话回复"解析：不同核心措辞不一样，解析要按结构而不是按整句。
final class PlayerListParserTests: XCTestCase {

    // MARK: - list

    func testParsesOnlinePlayers() {
        let reply = "There are 2 of a max of 20 players online: alice, bob"
        XCTAssertEqual(PlayerListParser.onlinePlayers(from: reply), ["alice", "bob"])
    }

    func testEmptyOnlineList() {
        XCTAssertEqual(
            PlayerListParser.onlinePlayers(from: "There are 0 of a max of 20 players online:"),
            []
        )
    }

    // MARK: - whitelist

    func testParsesWhitelist() {
        XCTAssertEqual(
            PlayerListParser.whitelisted(from: "There are 2 whitelisted player(s): alice, bob"),
            ["alice", "bob"]
        )
        XCTAssertEqual(
            PlayerListParser.whitelisted(from: "There are 1 whitelisted players: alice"),
            ["alice"]
        )
    }

    // MARK: - banlist

    func testParsesBanListWithReasons() {
        let reply = "There are 2 ban(s):\nalice (griefing), bob (cheating)"
        let banned = PlayerListParser.banned(from: reply)
        XCTAssertEqual(banned.map(\.name), ["alice", "bob"])
        XCTAssertEqual(banned.map(\.reason), ["griefing", "cheating"])
    }

    func testBanWithoutReason() {
        let reply = "There are 1 ban(s): alice"
        XCTAssertEqual(PlayerListParser.banned(from: reply).map(\.name), ["alice"])
        XCTAssertNil(PlayerListParser.banned(from: reply).first?.reason)
    }

    func testBanDashMeansNone() {
        XCTAssertTrue(PlayerListParser.banned(from: "There are 0 ban(s): -").isEmpty)
    }

    func testIgnoresNonPlayerSentences() {
        XCTAssertEqual(PlayerListParser.onlinePlayers(from: "Unknown command"), [])
        XCTAssertEqual(PlayerListParser.onlinePlayers(from: ""), [])
        XCTAssertEqual(PlayerListParser.whitelisted(from: "§cNo whitelist"), [])
    }

    func testOneNamePerLine() {
        let reply = "Banned players:\nalice\nbob"
        XCTAssertEqual(PlayerListParser.banned(from: reply).map(\.name), ["alice", "bob"])
    }
}
