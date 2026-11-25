@testable import UseCasesCore

/// A calendar that says the day the test decides.
struct MockCalendarDay: CalendarDayTelling {
  let day: String

  init(_ day: String = "2026-10-20") {
    self.day = day
  }

  func today() -> String {
    day
  }
}
