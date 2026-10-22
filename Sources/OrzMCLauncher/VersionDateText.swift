import Foundation

/// 版本清单里的日期文案：近期用「今天 / 昨天 / N 天前」，久远的用本地化绝对日期。
///
/// 为什么返回枚举而不是成品字符串：
/// - 清单行要在**模型层**拼副标题（日期 · 已装内容），又想能单测；
/// - 「今天 / 昨天 / N 天前」需要跟应用其他文案一起进 `Localizable.xcstrings`，
///   而 `Sources/*` 是共享 target，不能依赖 app 的文案表；
/// - 所以这里只做**判定**（今天/昨天/几天前/绝对日期），文案由视图层本地化。
public enum VersionDateText {
    /// 超过这个天数就显示绝对日期（版本列表里大多是几个月前的版本）。
    public static let relativeWindowDays = 8

    /// 日级判定结果。
    public enum Day: Equatable, Sendable {
        case today
        case yesterday
        /// 2–7 天前。
        case daysAgo(Int)
        /// 已本地化的绝对日期（`2025-03-25` 这类）。
        case absolute(String)
    }

    /// 解析清单里的 ISO 8601 时间（如 `2025-03-25T12:14:58+00:00`）。
    public static func parse(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        return try? Date(raw, strategy: .iso8601)
    }

    /// 日级判定（`now` / `locale` / `calendar` 可注入，便于单测）。
    public static func day(
        for date: Date,
        now: Date = .now,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> Day {
        var calendar = calendar
        calendar.locale = locale
        let start = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: start, to: today).day ?? 0

        switch days {
        case 0: return .today
        case 1: return .yesterday
        case 2..<relativeWindowDays: return .daysAgo(days)
        default:
            // 未来时间（清单异常）或太久远：给绝对日期，别显示「上周」这种模糊说法。
            return .absolute(date.formatted(.dateTime.year().month().day().locale(locale)))
        }
    }

    /// 时刻（精确到秒，用于「版本信息更新于」这种时间戳）。
    public static func timeText(for date: Date, locale: Locale = .current) -> String {
        date.formatted(.dateTime.hour().minute().second().locale(locale))
    }
}
