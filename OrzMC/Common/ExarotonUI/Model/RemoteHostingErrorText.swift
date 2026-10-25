//
//  RemoteHostingErrorText.swift
//  OrzMC
//

import Foundation
import OpenAPIRuntime

/// 把远程托管（exaroton，以及将来的 MCSM）的网络 / HTTP 错误翻译成**一句能读懂的话**。
///
/// 为什么需要它（2026-10-25 真机反馈）：额度池请求被取消时，弹窗正文是原始 `NSError`：
///
/// ```
/// Failed to fetch credit pool info: Client encountered an error invoking the operation
/// "getCreditPool", caused by "Transport threw an error.", underlying error:
/// Error Domain=NSURLErrorDomain Code=-999 "已取消" UserInfo={NSURLErrorFailingURLStringKey=…}
/// ```
///
/// 两个问题：
/// 1. `-999` 是「任务被取消」（视图消失 / `ConnectionEpoch` 换代 / 请求被替换），**不是错误**；
/// 2. 即便是真错误，也不该把 `localizedDescription` 直接给用户看（英文、嵌套、URL、内部类名）。
///
/// 约定：`describe(_:)` **只返回用户可见的一句话**，返回 `nil` 表示「不要打扰用户」
/// （调用方据此不弹 alert）。任何情况下都不把原始 `NSError` 转储露出去。
enum RemoteHostingErrorText {

    /// 错误类别（纯值，便于单测；不持有任何界面文案）。
    enum Kind: Equatable {
        /// 任务被取消 / 连接被替换：静默。
        case cancelled
        /// 没网、连不上、超时：同一句提示就够。
        case offline
        /// 401 / 403：Token 失效或没权限。
        case unauthorized
        /// 拿到了 HTTP 状态码但服务不可用（5xx 及其他）。
        case server(Int)
        /// 兜底：不认识的错误，只给一句通用提示。
        case unknown
    }

    /// 分类：先剥掉 OpenAPI 运行时的 `ClientError` 外壳，再按底层错误 / HTTP 状态判断。
    static func kind(of error: Error) -> Kind {
        let unwrapped = unwrap(error)
        if isCancellation(unwrapped.error) { return .cancelled }
        if isOffline(unwrapped.error) { return .offline }
        if let status = unwrapped.status {
            if status == 401 || status == 403 { return .unauthorized }
            return .server(status)
        }
        return .unknown
    }

    /// 用户可见的一句话；`nil` = 不用提示（取消类）。
    static func describe(_ error: Error) -> String? {
        switch kind(of: error) {
        case .cancelled:
            return nil
        case .offline:
            return String(localized: "Can't reach the remote service. Check your connection and try again.")
        case .unauthorized:
            return String(localized: "Your exaroton token is no longer valid. Please sign in again.")
        case .server(let status):
            return String(localized: "The remote service is temporarily unavailable (HTTP \(status)). Try again later.")
        case .unknown:
            return String(localized: "The remote service did not answer as expected. Try again later.")
        }
    }

    // MARK: - 内部

    /// 一路剥壳：`ClientError`（OpenAPI 运行时包装）与 `NSError` 的 `NSUnderlyingErrorKey`。
    /// 同时把能拿到的 HTTP 状态码带出来（`ClientError.response`）。
    private static func unwrap(_ error: Error) -> (status: Int?, error: Error) {
        var status: Int?
        var current = error
        // 防御环形引用：正常嵌套不会超过两三层。
        for _ in 0..<8 {
            if let clientError = current as? ClientError {
                if status == nil { status = clientError.response?.status.code }
                current = clientError.underlyingError
                continue
            }
            let nsError = current as? NSError
            if let underlying = nsError?.userInfo[NSUnderlyingErrorKey] as? Error {
                current = underlying
                continue
            }
            break
        }
        return (status, current)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled { return true }
        if nsError.domain == NSCocoaErrorDomain, nsError.code == NSUserCancelledError { return true }
        return false
    }

    private static func isOffline(_ error: Error) -> Bool {
        guard let urlError = error as? URLError ?? urlErrorFromNSError(error) else { return false }
        switch urlError.code {
        case .notConnectedToInternet,
             .networkConnectionLost,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .dataNotAllowed,
             .internationalRoamingOff,
             .secureConnectionFailed:
            return true
        default:
            return false
        }
    }

    /// `URLSession` 的错误常常以 `NSError` 形式冒出来（塞在 `ClientError.underlyingError` 里就是这样），
    /// 只有 domain + code 两个字段可用。
    private static func urlErrorFromNSError(_ error: Error) -> URLError? {
        let nsError = error as NSError
        guard nsError.domain == NSURLErrorDomain else { return nil }
        return URLError(URLError.Code(rawValue: nsError.code))
    }
}
