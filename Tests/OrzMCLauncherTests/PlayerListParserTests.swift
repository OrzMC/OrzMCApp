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

    /// 真机实测：`banlist list` 在 Paper 上是错误命令，服务端回
    /// `Unknown or incomplete command …` + `banlist list<--[HERE]`。
    /// 旧实现把第二行当成了玩家名（"封禁列表里有一项 banlist list<--[HERE]"）。
    func testCommandErrorReplyIsNotParsedAsPlayer() {
        let reply = """
        Unknown or incomplete command, see below for error
        banlist list<--[HERE]
        """
        XCTAssertTrue(PlayerListParser.isCommandError(reply))
        XCTAssertTrue(PlayerListParser.banned(from: reply).isEmpty)
        XCTAssertTrue(PlayerListParser.onlinePlayers(from: reply).isEmpty)
        XCTAssertTrue(PlayerListParser.whitelisted(from: reply).isEmpty)
    }

    /// `banlist`（不带 list）是标准写法：一行一个名字 + 原因。
    func testBanlistParsesNamesWithReason() {
        let reply = """
        There are 2 ban(s):
        alice (griefing)
        bob
        """
        let bans = PlayerListParser.banned(from: reply)
        XCTAssertEqual(bans.map(\.name), ["alice", "bob"])
        XCTAssertEqual(bans.first?.reason, "griefing")
    }

    /// "没有人被封禁"这种没有名单正文的回复，不能解析出假玩家。
    func testEmptyBanlistYieldsNoPlayers() {
        XCTAssertTrue(PlayerListParser.banned(from: "There are no bans.").isEmpty)
        XCTAssertTrue(PlayerListParser.banned(from: "There are 0 ban(s):").isEmpty)
    }
}
