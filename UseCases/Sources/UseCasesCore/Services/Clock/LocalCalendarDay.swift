import Foundation

/// The calendar day of the clock in a time zone: the machine's own unless a test says another.
struct LocalCalendarDay: CalendarDayTelling {
  private let timekeeper: any Timekeeping
  private let timeZone: TimeZone

  init(
    timekeeper: any Timekeeping = SystemTimekeeper(),
    timeZone: TimeZone = .current,
  ) {
    self.timekeeper = timekeeper
    self.timeZone = timeZone
  }

  func today() -> String {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone

    let day = calendar.dateComponents(
      [.year, .month, .day],
      from: timekeeper.now(),
    )

    return [
      Self.padded(day.year ?? 0, to: 4),
      Self.padded(day.month ?? 0, to: 2),
      Self.padded(day.day ?? 0, to: 2),
    ].joined(separator: "-")
  }

  private static func padded(
    _ number: Int,
    to width: Int,
  ) -> String {
    let digits = String(number)

    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }
}
