import XCTest
@testable import OrzMCLauncher

/// 版本日期判定：今天 / 昨天 / N 天前 / 绝对日期（固定 now 与 locale，结果可断言）。
final class VersionDateTextTests: XCTestCase {
    private let locale = Locale(identifier: "zh_Hans_CN")
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    private func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }

    private var now: Date { date("2026-10-22T12:00:00Z") }

    func testParsesMojangReleaseTime() {
        XCTAssertNotNil(VersionDateText.parse("2025-03-25T12:14:58+00:00"))
        XCTAssertNil(VersionDateText.parse(nil))
        XCTAssertNil(VersionDateText.parse(""))
        XCTAssertNil(VersionDateText.parse("not-a-date"))
    }

    func testTodayAndYesterday() {
        XCTAssertEqual(
            VersionDateText.day(for: date("2026-10-22T08:00:00Z"), now: now, locale: locale, calendar: calendar),
            .today
        )
        XCTAssertEqual(
            VersionDateText.day(for: date("2026-10-21T23:00:00Z"), now: now, locale: locale, calendar: calendar),
            .yesterday
        )
    }

    func testRecentDaysInsideWindow() {
        XCTAssertEqual(
            VersionDateText.day(for: date("2026-10-19T08:00:00Z"), now: now, locale: locale, calendar: calendar),
            .daysAgo(3)
        )
        XCTAssertEqual(
            VersionDateText.day(for: date("2026-10-15T08:00:00Z"), now: now, locale: locale, calendar: calendar),
            .daysAgo(7)
        )
    }

    func testOlderDatesBecomeAbsolute() {
        guard case let .absolute(text) = VersionDateText.day(
            for: date("2025-03-25T12:14:58Z"), now: now, locale: locale, calendar: calendar
        ) else {
            return XCTFail("超过相对窗口应给绝对日期")
        }
        XCTAssertTrue(text.contains("2025"), text)
    }

    func testFutureDatesBecomeAbsolute() {
        guard case .absolute = VersionDateText.day(
            for: date("2026-11-01T08:00:00Z"), now: now, locale: locale, calendar: calendar
        ) else {
            return XCTFail("未来时间应给绝对日期，而不是「-3 天前」")
        }
    }

    func testTimeTextHasHourMinuteAndSecond() {
        let text = VersionDateText.timeText(for: date("2026-10-22T06:32:07Z"), locale: locale)
        XCTAssertEqual(text.filter { $0 == ":" }.count, 2, "精确到秒：\(text)")
        XCTAssertTrue(text.hasSuffix("07"), text)
    }
}
