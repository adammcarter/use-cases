/// Tells today's date as people on this machine count it: a sign-off is dated by the calendar
/// day of the person who gave it.
protocol CalendarDayTelling: Sendable {
  /// Today, written `YYYY-MM-DD`.
  func today() -> String
}
