import Foundation
import Testing
@testable import UseCasesCore

struct LocalCalendarDayTests {
  private func day(
    at instant: String,
    hoursFromUTC: Int,
  ) throws -> String {
    let date = try #require(ISO8601DateFormatter().date(from: instant))
    let zone = try #require(TimeZone(secondsFromGMT: hoursFromUTC * 3600))

    return LocalCalendarDay(
      timekeeper: FixedTimekeeper(date: date),
      timeZone: zone,
    ).today()
  }

  @Test(arguments: [
    ("2026-10-19T23:30:00Z", 0, "2026-10-19"),
    ("2026-10-19T23:30:00Z", 14, "2026-10-20"),
    ("2026-10-20T00:30:00Z", -1, "2026-10-19"),
    ("2026-10-20T01:30:00Z", -12, "2026-10-19"),
    ("2026-01-05T12:00:00Z", 0, "2026-01-05"),
    ("2026-12-31T23:59:59Z", 0, "2026-12-31"),
    ("2026-12-31T23:59:59Z", 1, "2027-01-01"),
    ("2028-02-29T12:00:00Z", 0, "2028-02-29"),
  ])
  func `the day is the calendar day where the clock is read, not the UTC one`(
    instant: String,
    hoursFromUTC: Int,
    expected: String,
  ) throws {
    #expect(try day(at: instant, hoursFromUTC: hoursFromUTC) == expected)
  }
}
