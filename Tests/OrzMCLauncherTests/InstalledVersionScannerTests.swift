import XCTest
@testable import OrzMCLauncher

/// 安装状态扫描：视图里不再逐行做文件 IO（这里用注入的 exists 验证判定规则）。
final class InstalledVersionScannerTests: XCTestCase {
    func testNothingInstalled() {
        let scanner = InstalledVersionScanner { _ in false }
        let state = scanner.state(
            clientDir: "/root/versions/1.21.5",
            serverDirs: [("paper", "/root/servers/1.21.5/paper")]
        )
        XCTAssertTrue(state.isEmpty)
        XCTAssertEqual(state.symbolName, "cube")
        XCTAssertTrue(state.labels.isEmpty)
    }

    func testClientAndServers() {
        let existing: Set<String> = ["/c/1.21.5", "/s/1.21.5/paper", "/s/1.21.5/vanilla"]
        let scanner = InstalledVersionScanner { existing.contains($0) }
        let state = scanner.state(
            clientDir: "/c/1.21.5",
            serverDirs: [
                ("paper", "/s/1.21.5/paper"),
                ("vanilla", "/s/1.21.5/vanilla"),
                ("fabric", "/s/1.21.5/fabric"),
            ]
        )
        XCTAssertTrue(state.hasClient)
        XCTAssertEqual(state.servers, ["paper", "vanilla"], "只算真存在的目录，且保持传入顺序")
        XCTAssertEqual(state.labels, ["Client", "Paper server", "Vanilla server"])
        XCTAssertEqual(state.symbolName, "macbook", "装了客户端就显示客户端图标")
    }

    func testServerOnly() {
        let scanner = InstalledVersionScanner { $0 == "/s/1.20.6/paper" }
        let state = scanner.state(
            clientDir: "/c/1.20.6",
            serverDirs: [("paper", "/s/1.20.6/paper")]
        )
        XCTAssertFalse(state.hasClient)
        XCTAssertTrue(state.hasServer)
        XCTAssertEqual(state.symbolName, "xserve")
        XCTAssertEqual(state.labels, ["Paper server"])
    }

    func testNilClientDirIsTreatedAsAbsent() {
        let scanner = InstalledVersionScanner { _ in true }
        let state = scanner.state(clientDir: nil, serverDirs: [])
        XCTAssertFalse(state.hasClient)
    }
}
