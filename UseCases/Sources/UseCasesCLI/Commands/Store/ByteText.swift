/// A size as a person reads it: `512 B`, `1.2 MB`, `450 MB`. Units step by 1000; below 10 a
/// unit keeps one decimal.
enum ByteText {
  private static let units = ["KB", "MB", "GB", "TB"]

  static func text(_ bytes: Int64) -> String {
    guard bytes >= 1000 else {
      return "\(bytes) B"
    }

    var value = Double(bytes) / 1000
    var unit = 0

    while value >= 999.5, unit < units.count - 1 {
      value /= 1000
      unit += 1
    }

    let number = value < 9.95
      ? String(Double((value * 10).rounded()) / 10)
      : String(Int(value.rounded()))

    return "\(number) \(units[unit])"
  }
}
