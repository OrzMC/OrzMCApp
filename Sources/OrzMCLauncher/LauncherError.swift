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

    /// 面向用户的中文一句话（按错误码归类；`nil` = 没有额外提示）。
    ///
    /// 引擎抛出的 `message` 有时是英文（网络层/第三方库），直接弹出来就成了中英混排。
    /// 这里按规范错误码给一句中文结论，原始信息原样保留在第二行（便于上报对照）。
    public var codeHint: String? {
        Self.hint(for: code)
    }

    /// 原始信息是否已经是中文（含 CJK 就不再加提示，避免重复）。
    public var messageIsChinese: Bool {
        message.unicodeScalars.contains { scalar in
            (0x4E00...0x9FFF).contains(scalar.value)      // 基本汉字
                || (0x3400...0x4DBF).contains(scalar.value)
        }
    }

    public static func hint(for code: String) -> String? {
        switch code {
        case "E_USAGE":
            return String(localized: "The input isn't valid. Check the settings and try again.")
        case "E_NETWORK":
            return String(localized: "Network request failed. Check your connection and try again.")
        case "E_VERIFY", "E_VERSION_NOT_FOUND", "E_NOT_FOUND":
            return String(localized: "The requested version or file doesn't exist. Refresh the list and try again.")
        case "E_AUTH", "E_AUTH_EXPIRED", "E_AUTH_DENIED", "E_AUTH_LOCKED",
             "E_AUTH_XBOX", "E_AUTH_NO_GAME", "E_AUTH_NOT_CONFIGURED":
            return String(localized: "Sign-in failed. Complete the Microsoft sign-in again.")
        case "E_UNSUPPORTED", "E_UNSUPPORTED_TYPE", "E_UNSUPPORTED_OP":
            return String(localized: "This version or platform doesn't support that action.")
        case "E_IO":
            return String(localized: "Reading or writing files failed. Check free space and permissions.")
        case "E_CANCELLED":
            return String(localized: "Cancelled.")
        case "E_RUNTIME", "E_INTERNAL":
            return String(localized: "Something went wrong while running the game or server.")
        default:
            return nil
        }
    }

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
