import Foundation

/// `new Date(milliseconds).toISOString()`: `YYYY-MM-DDTHH:mm:ss.sssZ` in UTC,
/// with a signed six-digit year outside 0000–9999.
enum JavaScriptTimestamp {
  static func isoString(milliseconds: Double) -> String {
    let total = Int64(milliseconds)
    let millisecondsPerDay: Int64 = 86_400_000
    let days = floorDivision(total, millisecondsPerDay)
    let timeOfDay = total - days * millisecondsPerDay
    let date = civilDate(daysSinceEpoch: days)

    let year = if (0 ... 9999).contains(date.year) {
      padded(date.year, width: 4)
    } else {
      (date.year < 0 ? "-" : "+") + padded(abs(date.year), width: 6)
    }
    let hours = timeOfDay / 3_600_000
    let minutes = timeOfDay / 60000 % 60
    let seconds = timeOfDay / 1000 % 60
    let fraction = timeOfDay % 1000
    return "\(year)-\(padded(date.month, width: 2))-\(padded(date.day, width: 2))"
      + "T\(padded(hours, width: 2)):\(padded(minutes, width: 2)):\(padded(seconds, width: 2))"
      + ".\(padded(fraction, width: 3))Z"
  }

  private static func floorDivision(
    _ dividend: Int64,
    _ divisor: Int64,
  ) -> Int64 {
    let quotient = dividend / divisor
    return dividend % divisor < 0 ? quotient - 1 : quotient
  }

  /// Howard Hinnant's `civil_from_days`, proleptic Gregorian.
  private static func civilDate(daysSinceEpoch: Int64) -> CivilDate {
    let shifted = daysSinceEpoch + 719_468
    let era = floorDivision(shifted, 146_097)
    let dayOfEra = shifted - era * 146_097
    let yearOfEra = (dayOfEra - dayOfEra / 1460 + dayOfEra / 36524 - dayOfEra / 146_096) / 365
    let dayOfYear = dayOfEra - (365 * yearOfEra + yearOfEra / 4 - yearOfEra / 100)
    let shiftedMonth = (5 * dayOfYear + 2) / 153
    let day = dayOfYear - (153 * shiftedMonth + 2) / 5 + 1
    let month = shiftedMonth < 10 ? shiftedMonth + 3 : shiftedMonth - 9
    let year = yearOfEra + era * 400 + (month <= 2 ? 1 : 0)
    return CivilDate(year: year, month: month, day: day)
  }

  private struct CivilDate {
    let year: Int64
    let month: Int64
    let day: Int64
  }

  private static func padded(
    _ value: Int64,
    width: Int,
  ) -> String {
    let digits = String(value)
    return String(repeating: "0", count: max(0, width - digits.count)) + digits
  }
}

/// The TypeScript's `uuidv7()`: the clock's milliseconds as at least twelve
/// hex digits, then 18 of the 20 hex digits of ten random bytes — the last
/// two are drawn and never used.
enum EvidenceEventIdentifier {
  static func make(
    milliseconds: Double,
    randomBytes: [UInt8],
  ) -> String {
    let timestamp = Array(padded(String(Int64(milliseconds), radix: 16), width: 12))
    let random = Array(randomBytes.map { byte in
      String(format: "%02x", byte)
    }.joined())
    func text(
      _ characters: [Character],
      _ range: Range<Int>,
    ) -> String {
      String(characters[min(range.lowerBound, characters.count) ..< min(
        range.upperBound,
        characters.count,
      )])
    }
    return [
      text(timestamp, 0 ..< 8),
      text(timestamp, 8 ..< 12),
      "7" + text(random, 0 ..< 3),
      "8" + text(random, 3 ..< 6),
      text(random, 6 ..< 18),
    ].joined(separator: "-")
  }

  private static func padded(
    _ text: String,
    width: Int,
  ) -> String {
    String(repeating: "0", count: max(0, width - text.count)) + text
  }
}
