import Foundation

/// 进度单位：`items` = 文件数，`bytes` = 字节数（引擎 `LaunchProgress.Kind` 的平台无关镜像）。
public enum ProgressUnit: String, Sendable {
    case items
    case bytes
}

/// 启动/下载进度的**单一**状态（取代 GUI 里 6 个 `progress*` 字段的散装镜像）。
///
/// 规则（父仓库 `docs/spec/behavior.md` B8）：`fraction == nil` 表示**不定长**，
/// UI 不得画假进度条，只能显示"正在做什么"。
public struct LaunchProgressState: Equatable, Sendable {
    public var label: String
    public var completed: Int64
    public var total: Int64?
    public var unit: ProgressUnit
    public var fraction: Double?

    public init(
        label: String = "",
        completed: Int64 = 0,
        total: Int64? = nil,
        unit: ProgressUnit = .items,
        fraction: Double? = nil
    ) {
        self.label = label
        self.completed = completed
        self.total = total
        self.unit = unit
        self.fraction = fraction
    }

    public static let idle = LaunchProgressState()

    /// 不定长：有阶段在跑但拿不到总量。
    public var isIndefinite: Bool { fraction == nil && (completed > 0 || !label.isEmpty) }

    /// 是否应该显示进度 UI（`0 < fraction < 1` 或不定长）。
    public var isRunning: Bool {
        if let fraction { return fraction > 0 && fraction < 1 }
        return isIndefinite
    }

    public var isFinished: Bool {
        if let fraction { return fraction >= 1 }
        return false
    }

    /// 进度文案：有总量显示「已完成 / 总量」，否则退回百分比或阶段标题。
    public var summary: String {
        if let total, total > 0 {
            switch unit {
            case .bytes:
                return "\(Self.byteText(completed)) / \(Self.byteText(total))"
            case .items:
                return "\(completed) / \(total)"
            }
        }
        if let fraction, fraction > 0 {
            return String(format: "%.0f%%", fraction * 100)
        }
        return label
    }

    /// 人类可读字节数。
    public static func byteText(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}

/// 游戏模式（`client` = 客户端，`server` = 服务端）。
///
/// 刻意**不**叫 `GameType`：引擎已有 `Game.GameType`（vanilla/paper/fabric/forge），
/// 两者同名不同义，历史上最容易读错。
public enum GameMode: String, CaseIterable, Identifiable, Sendable {
    case client
    case server

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .client: return "Client"
        case .server: return "Server"
        }
    }
}
