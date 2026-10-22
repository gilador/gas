import XCTest
@testable import UsageCore

final class ResetTimeTests: XCTestCase {
    private let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0, _ second: Double = 0) -> Date {
        let base = calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute, second: Int(second)))!
        return base.addingTimeInterval(second - second.rounded(.down))
    }

    private var now: Date { date(22, 10) }

    private func text(_ reset: Date) -> String {
        ResetTime.text(for: reset, now: now, calendar: calendar)
    }

    func testSameDayOnTheHour() {
        XCTAssertEqual(text(date(22, 16)), "at 4pm")
    }

    func testSameDayWithMinutes() {
        XCTAssertEqual(text(date(22, 16, 30)), "at 4:30pm")
        XCTAssertEqual(text(date(22, 21, 5)), "at 9:05pm")
    }

    func testTomorrowShowsWeekday() {
        XCTAssertEqual(text(date(23, 2)), "on Friday at 2am")
    }

    func testSixDaysAwayShowsWeekday() {
        XCTAssertEqual(text(date(28, 2)), "on Wednesday at 2am")
    }

    func testSevenDaysAwayShowsDate() {
        XCTAssertEqual(text(date(29, 2)), "on Oct 29 at 2am")
    }

    func testMidnightAndNoon() {
        XCTAssertEqual(text(date(23, 0)), "on Friday at 12am")
        XCTAssertEqual(text(date(22, 12)), "at 12pm")
    }

    func testRoundsToNearestMinute() {
        XCTAssertEqual(text(date(23, 1, 59, 59.6)), "on Friday at 2am")
    }

    func testRoundingAcrossMidnightUsesRoundedDay() {
        XCTAssertEqual(text(date(22, 23, 59, 45)), "on Friday at 12am")
    }

    func testPastIsNow() {
        XCTAssertEqual(text(date(22, 9)), "now")
        XCTAssertEqual(text(now), "now")
    }

    private func remaining(_ seconds: TimeInterval) -> String {
        ResetTime.remaining(until: now.addingTimeInterval(seconds), now: now)
    }

    func testRemainingDaysHoursMinutes() {
        XCTAssertEqual(remaining(6 * 86400 + 3 * 3600 + 12 * 60), "6 days, 3 hours and 12 minutes left")
    }

    func testRemainingOmitsZeroParts() {
        XCTAssertEqual(remaining(2 * 3600), "2 hours left")
        XCTAssertEqual(remaining(86400 + 5 * 60), "1 day and 5 minutes left")
    }

    func testRemainingRoundsUpToMinute() {
        XCTAssertEqual(remaining(34), "1 minute left")
        XCTAssertEqual(remaining(3600 + 1), "1 hour and 1 minute left")
    }

    func testRemainingExactDay() {
        XCTAssertEqual(remaining(86400), "1 day left")
    }

    func testRemainingPastIsResettingNow() {
        XCTAssertEqual(remaining(-60), "Resetting now")
        XCTAssertEqual(remaining(0), "Resetting now")
    }
}
