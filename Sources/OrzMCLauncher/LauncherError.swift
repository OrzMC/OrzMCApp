import Foundation

/// 带规范错误码的错误（`E_*`，见父仓库 `docs/spec/cli-surface.md` §6.1）。
///
/// 引擎侧的错误类型大多已有 `code`；GUI 曾经把它们压成
/// `error.localizedDescription` 字符串，用户只看到 "Failed to start client: …"，
/// 拿不到 `E_VERIFY` / `E_AUTH_EXPIRED` 这类**可操作**的信息。
public protocol CodedError {
    var code: String { get }
}

extension CodedError where Self: Error {
    var codedMessage: String { (self as Error).localizedDescription }
}

/// GUI 侧统一错误：**保留 code**，文案给用户看。
public struct LauncherError: Error, Equatable, Sendable, CustomStringConvertible {
    /// 规范错误码（`E_USAGE` / `E_NETWORK` / `E_VERIFY` / `E_AUTH*` / `E_RUNTIME` …）。
    public let code: String
    /// 面向用户的一句话（可含底层描述）。
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var description: String { "\(message) (\(code))" }

    /// 从任意错误提取：能拿到 `code` 就保留，拿不到用调用方给的兜底码。
    ///
    /// 兜底码由调用点决定（启动失败 → `E_RUNTIME`，版本目录拉取失败 → `E_NETWORK`），
    /// 这样 UI 永远能同时显示"发生了什么"和"属于哪类问题"。
    public static func wrap(_ error: Error, fallbackCode: String) -> LauncherError {
        if let coded = error as? CodedError {
            return LauncherError(code: coded.code, message: message(of: error))
        }
        return LauncherError(code: fallbackCode, message: message(of: error))
    }

    /// 文案优先用错误自身的描述（引擎的错误类型都实现了 `CustomStringConvertible`，
    /// 写的是人话）；只有 NSError 系才退回 `localizedDescription`。
    static func message(of error: Error) -> String {
        // NSError 的 `description` 是 "Error Domain=… UserInfo=…" 这种调试串，得用 localizedDescription。
        if type(of: error) is NSError.Type {
            return (error as NSError).localizedDescription
        }
        if let described = error as? CustomStringConvertible {
            return described.description
        }
        return (error as NSError).localizedDescription
    }
}
