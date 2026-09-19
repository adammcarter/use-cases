import Foundation

/// `Date.parse` as V8 answers it for the ES5 date-time string format, in epoch
/// milliseconds, or nil where V8 answers NaN.
///
/// V8 reads `[+|-YY]YYYY[-MM[-DD]][THH:mm[:ss[.s+]][Z|±hh:mm|±hhmm]]`, with a
/// case-insensitive `T` and `Z`, a day of 01–31 whatever the month (an overflow
/// rolls into the next month), `24:00` only when everything after it is zero,
/// and any number of fraction digits truncated to milliseconds. Anything that
/// is not in that shape V8 hands to its LEGACY parser (`"Jan 1 2026"`,
/// `"2026/01/01"`, `"2026-01-01 00:00:00Z"`); that parser is not ported, and
/// such text reads as nil here.
enum JavaScriptDate {
  /// The largest magnitude a JavaScript time value may have (TimeClip).
  private static let maximumTime: Double = 8.64e15

  static func parse(_ text: String) -> Double? {
    var reader = Reader(units: Array(text.utf16))
    guard let date = reader.readDate() else {
      return nil
    }
    guard !reader.isAtEnd else {
      return clip(days(date) * 86_400_000)
    }
    guard reader.skip(anyOf: [0x54, 0x74]), let time = reader.readTime() else {
      return nil
    }
    let offset: Double?
    if reader.skip(anyOf: [0x5A, 0x7A]) {
      offset = 0
    } else if let sign = reader.readSign() {
      guard let minutes = reader.readOffsetMinutes() else {
        return nil
      }
      offset = Double(sign * minutes) * 60000
    } else {
      offset = nil
    }
    guard reader.isAtEnd else {
      return nil
    }
    let local = days(date) * 86_400_000 + time
    guard let offset else {
      return clip(local - localOffset(atLocalMilliseconds: local))
    }
    return clip(local - offset)
  }

  private static func clip(_ time: Double) -> Double? {
    abs(time) <= maximumTime ? time : nil
  }

  /// Days since the epoch for a proleptic Gregorian date (MakeDay).
  private static func days(_ date: CalendarDate) -> Double {
    let year = date.year - (date.month <= 2 ? 1 : 0)
    let era = (year >= 0 ? year : year - 399) / 400
    let yearOfEra = year - era * 400
    let shiftedMonth = date.month > 2 ? date.month - 3 : date.month + 9
    let dayOfYear = (153 * shiftedMonth + 2) / 5
    let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
    return Double(era * 146_097 + dayOfEra - 719_468 + date.day - 1)
  }

  /// A date-time with no offset is LOCAL time in JavaScript.
  private static func localOffset(atLocalMilliseconds local: Double) -> Double {
    let seconds = TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: local / 1000))
    return Double(seconds) * 1000
  }

  private struct Reader {
    let units: [UInt16]
    var index = 0

    var isAtEnd: Bool {
      index == units.count
    }

    mutating func readDate() -> CalendarDate? {
      let year: Int
      if let sign = readSign() {
        guard let digits = readDigits(count: 6), !(sign < 0 && digits == 0) else {
          return nil
        }
        year = sign * digits
      } else {
        guard let digits = readDigits(count: 4) else {
          return nil
        }
        year = digits
      }
      guard skip(anyOf: [CodeUnits.hyphenMinus]) else {
        return CalendarDate(year: year, month: 1, day: 1)
      }
      guard let month = readDigits(count: 2), (1 ... 12).contains(month) else {
        return nil
      }
      guard skip(anyOf: [CodeUnits.hyphenMinus]) else {
        return CalendarDate(year: year, month: month, day: 1)
      }
      guard let day = readDigits(count: 2), (1 ... 31).contains(day) else {
        return nil
      }
      return CalendarDate(year: year, month: month, day: day)
    }

    /// `HH:mm[:ss[.fraction]]`, as milliseconds into the day.
    mutating func readTime() -> Double? {
      guard let hour = readDigits(count: 2), (0 ... 24).contains(hour),
            skip(anyOf: [CodeUnits.colon]),
            let minute = readDigits(count: 2), (0 ... 59).contains(minute)
      else {
        return nil
      }
      var second = 0
      var milliseconds = 0
      if skip(anyOf: [CodeUnits.colon]) {
        guard let value = readDigits(count: 2), (0 ... 59).contains(value) else {
          return nil
        }
        second = value
        if skip(anyOf: [CodeUnits.fullStop]) {
          guard let fraction = readFraction() else {
            return nil
          }
          milliseconds = fraction
        }
      }
      if hour == 24, minute + second + milliseconds > 0 {
        return nil
      }
      return Double(((hour * 60 + minute) * 60 + second) * 1000 + milliseconds)
    }

    /// `hh:mm` or `hhmm` after the sign, as minutes.
    mutating func readOffsetMinutes() -> Int? {
      let run = digitRun()
      if run == 4, let packed = readDigits(count: 4) {
        let hour = packed / 100
        let minute = packed % 100
        return hour <= 23 && minute <= 59 ? hour * 60 + minute : nil
      }
      guard let hour = readDigits(count: 2), hour <= 23,
            skip(anyOf: [CodeUnits.colon]),
            let minute = readDigits(count: 2), minute <= 59
      else {
        return nil
      }
      return hour * 60 + minute
    }

    /// One or more digits; the first three are the milliseconds.
    private mutating func readFraction() -> Int? {
      let run = digitRun()
      guard run > 0 else {
        return nil
      }
      var value = 0
      for offset in 0 ..< 3 {
        value *= 10
        if offset < run {
          value += Int(units[index + offset] - 0x30)
        }
      }
      index += run
      return value
    }

    mutating func readSign() -> Int? {
      guard index < units.count else {
        return nil
      }
      switch units[index] {
      case 0x2B:
        index += 1
        return 1
      case CodeUnits.hyphenMinus:
        index += 1
        return -1
      default:
        return nil
      }
    }

    mutating func skip(anyOf candidates: [UInt16]) -> Bool {
      guard index < units.count, candidates.contains(units[index]) else {
        return false
      }
      index += 1
      return true
    }

    /// Exactly `count` digits, and no more: V8 tokenizes a whole digit run and
    /// then asks for its length.
    private mutating func readDigits(count: Int) -> Int? {
      guard digitRun() == count else {
        return nil
      }
      var value = 0
      for offset in 0 ..< count {
        value = value * 10 + Int(units[index + offset] - 0x30)
      }
      index += count
      return value
    }

    private func digitRun() -> Int {
      var end = index
      while end < units.count, CodeUnits.isASCIIDigit(units[end]) {
        end += 1
      }
      return end - index
    }
  }
}

/// A proleptic Gregorian date as the ES5 grammar reads it; the day may exceed
/// the month's length, and rolls over.
private struct CalendarDate {
  let year: Int
  let month: Int
  let day: Int
}
