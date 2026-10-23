import XCTest
@testable import OrzMCLauncher

/// GUI 错误必须**保留规范错误码**（`E_*`），不能只剩 `localizedDescription`。
final class LauncherErrorTests: XCTestCase {
    private struct Coded: Error, CodedError, CustomStringConvertible {
        let code = "E_VERIFY"
        var description: String { "校验失败" }
    }

    private struct Plain: Error, CustomStringConvertible {
        var description: String { "网络断了" }
    }

    func testKeepsEngineCode() {
        let error = LauncherError.wrap(Coded(), fallbackCode: "E_RUNTIME")
        XCTAssertEqual(error.code, "E_VERIFY", "引擎给了码就用引擎的")
        XCTAssertEqual(error.message, "校验失败")
        XCTAssertEqual(error.description, "校验失败 (E_VERIFY)")
    }

    func testFallsBackToCallSiteCode() {
        let error = LauncherError.wrap(Plain(), fallbackCode: "E_NETWORK")
        XCTAssertEqual(error.code, "E_NETWORK")
        XCTAssertEqual(error.message, "网络断了")
    }

    func testNSERrorUsesLocalizedDescription() {
        let error = LauncherError.wrap(
            NSError(domain: "test", code: 7, userInfo: [NSLocalizedDescriptionKey: "磁盘满了"]),
            fallbackCode: "E_RUNTIME"
        )
        XCTAssertEqual(error.code, "E_RUNTIME")
        XCTAssertEqual(error.message, "磁盘满了")
    }

    // MARK: - 错误码 → 中文提示（`Operation Failed` 弹窗用）

    func testKnownCodesHaveHints() {
        for code in [
            "E_USAGE", "E_NETWORK", "E_VERIFY", "E_AUTH", "E_AUTH_EXPIRED",
            "E_UNSUPPORTED", "E_IO", "E_CANCELLED", "E_RUNTIME", "E_INTERNAL",
        ] {
            XCTAssertNotNil(LauncherError.hint(for: code), "missing hint for \(code)")
        }
    }

    func testUnknownCodeHasNoHint() {
        XCTAssertNil(LauncherError.hint(for: "E_SOMETHING_NEW"))
    }

    func testChineseMessageDetection() {
        XCTAssertTrue(LauncherError(code: "E_NETWORK", message: "无法获取最新版本信息").messageIsChinese)
        XCTAssertFalse(LauncherError(code: "E_NETWORK", message: "The request timed out.").messageIsChinese)
    }
}
