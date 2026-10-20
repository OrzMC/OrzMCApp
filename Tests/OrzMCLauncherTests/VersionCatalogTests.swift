import XCTest
@testable import OrzMCLauncher

/// 版本目录的**过滤与选择复原**逻辑（以前散在 `GameView` 的 `@State` 里，两处同步）。
///
/// 这里只测平台无关部分（`VersionListFilter`）；`VersionCatalogModel` 依赖
/// `MojangAPI.Version` 与网络加载器，属于 app target 内的集成层。
final class VersionCatalogTests: XCTestCase {
    private struct Fake: MinecraftVersionSummary {
        let minecraftVersionId: String
        let minecraftVersionKind: MinecraftVersionKind
    }

    private let versions: [Fake] = [
        Fake(minecraftVersionId: "1.21.5", minecraftVersionKind: .release),
        Fake(minecraftVersionId: "1.21.5-rc1", minecraftVersionKind: .snapshot),
        Fake(minecraftVersionId: "1.20.6", minecraftVersionKind: .release),
        Fake(minecraftVersionId: "a1.2.6", minecraftVersionKind: .oldAlpha),
    ]

    func testReleaseOnlyFilter() {
        let filtered = VersionListFilter().filter(
            versions: versions, searchText: "", releaseOnly: true)
        XCTAssertEqual(filtered.map(\.minecraftVersionId), ["1.21.5", "1.20.6"])
    }

    func testSearchIsCaseInsensitive() {
        let filtered = VersionListFilter().filter(
            versions: versions, searchText: "RC1", releaseOnly: false)
        XCTAssertEqual(filtered.map(\.minecraftVersionId), ["1.21.5-rc1"])
    }

    func testCombinedFilter() {
        let filtered = VersionListFilter().filter(
            versions: versions, searchText: "1.2", releaseOnly: false)
        XCTAssertEqual(
            filtered.map(\.minecraftVersionId),
            ["1.21.5", "1.21.5-rc1", "1.20.6", "a1.2.6"]
        )
    }
}
