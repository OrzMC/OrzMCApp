/// `install.conf` 的「谁装的 / 从哪来」语义（规范 `docs/spec/install-update.md` §3.1）。
///
/// 这段逻辑刻意放在**平台无关的 SwiftPM 目标**里（不依赖 SwiftUI/AppKit），
/// 这样 macOS 与 iOS 两个前端可以共用同一套判定，也能被单测覆盖。
public enum InstallSurface: String, CaseIterable, Sendable {
    /// 由终端里的安装器写入。
    case cli
    /// 由 GUI 触发安装（安装器由 GUI 调用）。
    case gui

    /// 展示文案：**不做文件推断**（规范 F1），只据记录里的 `surface` 字段。
    public var displayText: String {
        switch self {
        case .cli: return "installed from a terminal"
        case .gui: return "installed from this app"
        }
    }
}

/// 两条**发布通道**（同一份规范的两个发布源，见 `frontends.md` F1/F3）。
public enum InstallChannel: String, CaseIterable, Sendable {
    case python
    case swift

    public var title: String {
        switch self {
        case .python: return "Python CLI"
        case .swift: return "Swift CLI"
        }
    }

    /// 从 `install.conf` 的 `source` 反推通道（`source` 记录的是真实发布仓库）。
    ///
    /// 只做**字符串归属判定**，不是「前端身份推断」：`source` 本来就写明来自哪个仓库。
    public static func infer(source: String?) -> InstallChannel? {
        guard let source, !source.isEmpty else { return nil }
        let normalized = source.lowercased()
        if normalized.contains("orzpythonmc") { return .python }
        if normalized.contains("orzmckit") { return .swift }
        return nil
    }
}

/// GUI 侧对一条安装记录的**只读视图**（GUI 不写 `install.conf`，写入一律由安装器负责）。
public struct InstallRecordView: Equatable, Sendable {
    public let version: String
    public let binaryPath: String
    public let surface: String?
    public let source: String?
    public let completionFile: String?
    /// `install.conf` 自身的落点（便于排查「看的是哪个状态目录」）。
    public let recordPath: String
    public let binaryExists: Bool

    public init(
        version: String,
        binaryPath: String,
        surface: String?,
        source: String?,
        completionFile: String?,
        recordPath: String,
        binaryExists: Bool
    ) {
        self.version = version
        self.binaryPath = binaryPath
        self.surface = surface
        self.source = source
        self.completionFile = completionFile
        self.recordPath = recordPath
        self.binaryExists = binaryExists
    }

    /// 已知的安装前端（`nil` = 旧记录 / 未知，**不得据此报错**）。
    public var installSurface: InstallSurface? { surface.flatMap(InstallSurface.init(rawValue:)) }

    /// 展示文案（未知来源要如实说「未知」，不能猜成 cli）。
    public var surfaceText: String {
        installSurface?.displayText ?? "origin unknown (legacy record)"
    }

    public var channel: InstallChannel? { InstallChannel.infer(source: source) }

    /// 记录在、但可执行文件不在（被手动删/移动）——GUI 应提示重装而不是假装可用。
    public var isBroken: Bool { !binaryExists }

    /// 能不能原地升级：官方 `orzmc update` 会保留 `surface`/`source`（§3.1 / §9），
    /// 所以只要真身还在就走升级，而不是重跑安装器（那会把 `surface` 改成本应用）。
    public var canUpdateInPlace: Bool { binaryExists && !binaryPath.isEmpty }
}

public enum InstallSurfacePolicy {
    /// 安装器环境：`ORZMC_SURFACE` 决定记录里的「谁装的」（§3.1）。
    ///
    /// - 首次安装 / 重装：由本应用触发 → `gui`；
    /// - **升级**：不走安装器，走 `orzmc update`（保留原值），因此这里不需要 `keep` 之类的特例。
    public static func installerEnvironment(
        base: [String: String],
        surface: InstallSurface = .gui
    ) -> [String: String] {
        var environment = base
        environment["ORZMC_SURFACE"] = surface.rawValue
        return environment
    }

    /// 重装的确认文案要讲清「会把记录改成由本应用安装」，避免用户以为升级不改归属。
    public static func reinstallNotice() -> String {
        "Reinstalling rewrites install.conf: the record will then say it was installed by this app "
            + "(surface=gui). Use Update instead to keep the original origin."
    }
}
