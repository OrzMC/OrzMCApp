import XCTest
@testable import OrzMCLauncher

/// 详情页实例扫描：全部文件 IO 都在这里，必须能在后台线程跑（纯函数 + 注入环境）。
final class DetailInstanceScanTests: XCTestCase {

    /// `marked` 里缺失的 key 表示"没有标记文件"（返回 `nil`），用于验证旧安装推断。
    private func scanner(
        existing: Set<String>,
        marked: [String: Set<String>] = [:],
        legacy: [String: Set<String>] = [:]
    ) -> DetailInstanceScan {
        DetailInstanceScan(environment: .init(
            exists: { existing.contains($0) },
            markedKinds: { marked[$0] },
            legacyKinds: { dir, _ in legacy[dir] ?? [] }
        ))
    }

    private func clientInstance(root: String, kind: String = "Vanilla") -> DetailInstanceScan.Instance {
        .init(id: "client.Vanilla", clientKind: kind, rootPath: root, paths: [root, root + "/saves"])
    }

    func testReportsEntryExistencePerPath() {
        let marker = scanner(existing: ["/c", "/c/saves"])
        let result = marker.scan([clientInstance(root: "/c")], version: "1.21")
        XCTAssertEqual(result.entryExists["client.Vanilla"], ["/c": true, "/c/saves": true])
    }

    func testMissingPathsAreFalse() {
        let marker = scanner(existing: [])
        let result = marker.scan([clientInstance(root: "/c")], version: "1.21")
        XCTAssertEqual(result.entryExists["client.Vanilla"], ["/c": false, "/c/saves": false])
    }

    func testUsesMarkersWhenPresent() {
        let marker = scanner(existing: ["/c"], marked: ["/c": ["Fabric"]])
        let result = marker.scan([clientInstance(root: "/c", kind: "Fabric")], version: "1.21")
        XCTAssertEqual(result.markedKinds["client.Vanilla"], ["Fabric"])
    }

    func testFallsBackToLegacyInference() {
        let marker = scanner(existing: ["/c"], legacy: ["/c": ["Vanilla"]])
        let result = marker.scan([clientInstance(root: "/c")], version: "1.21")
        XCTAssertEqual(result.markedKinds["client.Vanilla"], ["Vanilla"])
    }

    /// 目录不存在时不该再去读标记/做推断（少两次无意义的 stat）。
    func testSkipsKindLookupForMissingRoot() {
        let marker = scanner(existing: [], legacy: ["/c": ["Vanilla"]])
        let result = marker.scan([clientInstance(root: "/c")], version: "1.21")
        XCTAssertNil(result.markedKinds["client.Vanilla"])
    }

    func testServersNeverGetKinds() {
        let server = DetailInstanceScan.Instance(
            id: "server.paper", clientKind: nil, rootPath: "/s", paths: ["/s"]
        )
        let result = scanner(existing: ["/s"], legacy: ["/s": ["Vanilla"]]).scan([server], version: "1.21")
        XCTAssertEqual(result.entryExists["server.paper"], ["/s": true])
        XCTAssertNil(result.markedKinds["server.paper"])
    }

    func testBackgroundScanMatchesSyncScan() async {
        let marker = scanner(existing: ["/c"], marked: ["/c": ["Vanilla"]])
        let input = [clientInstance(root: "/c")]
        let sync = marker.scan(input, version: "1.21")
        let background = await marker.scanInBackground(input, version: "1.21")
        XCTAssertEqual(sync, background)
    }
}
