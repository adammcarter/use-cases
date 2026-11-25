/// A JSON Schema `format` the checker enforces.
enum SchemaFormat: String, CaseIterable, Sendable {
  case date

  /// RFC 3339 `date-time`.
  case dateTime = "date-time"

  /// Whether a text is written in this format.
  func isValid(_ text: String) -> Bool {
    switch self {
    case .date: Self.isCalendarDate(text)
    case .dateTime: Self.isDateTime(text)
    }
  }

  /// `YYYY-MM-DD`, ASCII digits, naming a day that exists in the Gregorian calendar from year
  /// 0001 on: there is no year 0000.
  static func isCalendarDate(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    guard scalars.count == 10, scalars[4] == "-", scalars[7] == "-" else {
      return false
    }
    guard
      let year = number(scalars[0 ..< 4]),
      let month = number(scalars[5 ..< 7]),
      let day = number(scalars[8 ..< 10])
    else {
      return false
    }

    return year >= 1 && (1 ... 12).contains(month) && (1 ... daysIn(month: month, year: year))
      .contains(day)
  }

  static func number(_ digits: ArraySlice<Unicode.Scalar>) -> Int? {
    var value = 0
    for digit in digits {
      guard ("0" ... "9").contains(digit) else {
        return nil
      }
      value = value * 10 + Int(digit.value - 48)
    }

    return value
  }

  private static func daysIn(
    month: Int,
    year: Int,
  ) -> Int {
    switch month {
    case 2: isLeap(year) ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
  }

  private static func isLeap(_ year: Int) -> Bool {
    year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
  }
}
