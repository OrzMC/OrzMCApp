import Foundation
import HTTPTypes
import OpenAPIRuntime
import XCTest

@testable import OrzMC

/// 远程托管错误文案：**取消不弹窗、真错误只说人话、绝不泄露 `NSError` 转储**。
///
/// 起因：额度池请求被取消时弹窗正文是
/// `Failed to fetch credit pool info: Client encountered an error … Domain=NSURLErrorDomain Code=-999 …`。
final class RemoteHostingErrorTextTests: XCTestCase {

    // MARK: - 取消（静默）

    func testCancellationErrorIsSilent() {
        XCTAssertEqual(RemoteHostingErrorText.kind(of: CancellationError()), .cancelled)
        XCTAssertNil(RemoteHostingErrorText.describe(CancellationError()))
    }

    func testURLErrorCancelledIsSilent() {
        XCTAssertNil(RemoteHostingErrorText.describe(URLError(.cancelled)))
    }

    /// 真机上报的那个形态：`URLSession` 的 -999 以 `NSError` 冒出来，外面还包着 `ClientError`。
    func testWrappedNSURLErrorCancelledIsSilent() {
        let underlying = NSError(
            domain: NSURLErrorDomain,
            code: NSURLErrorCancelled,
            userInfo: ["NSURLErrorFailingURLStringKey": "https://api.exaroton.com/v1/billing/pools/x"]
        )
        let wrapped = clientError(underlying: underlying)
        XCTAssertEqual(RemoteHostingErrorText.kind(of: wrapped), .cancelled)
        XCTAssertNil(RemoteHostingErrorText.describe(wrapped))
    }

    // MARK: - 网络

    func testTimeoutMapsToOfflineSentence() {
        let text = try? XCTUnwrap(RemoteHostingErrorText.describe(URLError(.timedOut)))
        XCTAssertEqual(RemoteHostingErrorText.kind(of: URLError(.timedOut)), .offline)
        XCTAssertEqual(text, String(localized: "Can't reach the remote service. Check your connection and try again."))
    }

    func testNotConnectedToInternetIsOffline() {
        let nsError = NSError(domain: NSURLErrorDomain, code: URLError.notConnectedToInternet.rawValue)
        XCTAssertEqual(RemoteHostingErrorText.kind(of: nsError), .offline)
        XCTAssertNotNil(RemoteHostingErrorText.describe(nsError))
    }

    // MARK: - HTTP 状态

    func testUnauthorizedMapsToTokenSentence() {
        let error = clientError(status: 401, underlying: URLError(.badServerResponse))
        XCTAssertEqual(RemoteHostingErrorText.kind(of: error), .unauthorized)
        XCTAssertEqual(
            RemoteHostingErrorText.describe(error),
            String(localized: "Your exaroton token is no longer valid. Please sign in again.")
        )
    }

    func testForbiddenIsUnauthorizedToo() {
        XCTAssertEqual(RemoteHostingErrorText.kind(of: clientError(status: 403)), .unauthorized)
    }

    func testServerErrorKeepsStatusCode() {
        let error = clientError(status: 503)
        XCTAssertEqual(RemoteHostingErrorText.kind(of: error), .server(503))
        let text = RemoteHostingErrorText.describe(error) ?? ""
        XCTAssertTrue(text.contains("503"), text)
    }

    // MARK: - 兜底

    func testUnknownErrorNeverLeaksRawNSError() {
        let raw = NSError(
            domain: "SomeInternalDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Transport threw an error."]
        )
        let text = try? XCTUnwrap(RemoteHostingErrorText.describe(raw))
        XCTAssertEqual(RemoteHostingErrorText.kind(of: raw), .unknown)
        XCTAssertEqual(text, String(localized: "The remote service did not answer as expected. Try again later."))
        XCTAssertFalse(text?.contains("SomeInternalDomain") ?? true)
        XCTAssertFalse(text?.contains("Code=42") ?? true)
    }

    // MARK: - 构造

    private func clientError(
        status: Int? = nil,
        underlying: Error = URLError(.unknown)
    ) -> ClientError {
        ClientError(
            operationID: "getCreditPool",
            operationInput: (),
            response: status.map { HTTPResponse(status: .init(code: $0)) },
            causeDescription: "Transport threw an error.",
            underlyingError: underlying
        )
    }
}
