extension SchemaFormat {
  /// RFC 3339 as the schema validator the design is checked with reads it: a real calendar date,
  /// `T` or `t`, `HH:MM:SS` with an optional fraction of one digit or more, then `Z`, `z` or a
  /// `+HH:MM` or `-HH:MM` offset. ASCII digits only. A second of 60 is refused, as is year 0000.
  static func isDateTime(_ text: String) -> Bool {
    let scalars = Array(text.unicodeScalars)
    let minimumLength = 20

    guard scalars.count >= minimumLength, scalars[10] == "T" || scalars[10] == "t" else {
      return false
    }
    guard isCalendarDate(String(String.UnicodeScalarView(scalars[0 ..< 10]))) else {
      return false
    }
    guard isTimeOfDay(scalars[11 ..< 19]) else {
      return false
    }

    return isTimeSuffix(scalars[19...])
  }

  /// `HH:MM:SS`, hour to 23, minute and second to 59.
  private static func isTimeOfDay(_ scalars: ArraySlice<Unicode.Scalar>) -> Bool {
    let items = Array(scalars)
    guard items.count == 8, items[2] == ":", items[5] == ":" else {
      return false
    }
    guard
      let hour = number(items[0 ..< 2]),
      let minute = number(items[3 ..< 5]),
      let second = number(items[6 ..< 8])
    else {
      return false
    }

    return hour <= 23 && minute <= 59 && second <= 59
  }

  /// An optional fraction, then the offset.
  private static func isTimeSuffix(_ scalars: ArraySlice<Unicode.Scalar>) -> Bool {
    var rest = scalars

    if rest.first == "." {
      rest = rest.dropFirst()
      let digits = rest.prefix {
        ("0" ... "9").contains($0)
      }
      guard !digits.isEmpty else {
        return false
      }
      rest = rest.dropFirst(digits.count)
    }

    return isOffset(Array(rest))
  }

  private static func isOffset(_ items: [Unicode.Scalar]) -> Bool {
    if items == ["Z"] || items == ["z"] {
      return true
    }
    guard items.count == 6, items[0] == "+" || items[0] == "-", items[3] == ":" else {
      return false
    }
    guard let hour = number(items[1 ..< 3]), let minute = number(items[4 ..< 6]) else {
      return false
    }

    return hour <= 23 && minute <= 59
  }
}
