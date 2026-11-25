/// A limit on a file's size that it went past.
enum YAMLLimit: Equatable, Sendable {
  case nesting(maximum: Int)
  case values(maximum: Int)

  /// The count was crossed while an alias was being expanded.
  case aliasValues(maximum: Int)

  var message: String {
    switch self {
    case let .nesting(maximum):
      "this is nested deeper than \(Self.grouped(maximum)) levels"
    case let .values(maximum):
      "this file holds more than \(Self.grouped(maximum)) values"
    case let .aliasValues(maximum):
      "aliases here expand to more than \(Self.grouped(maximum)) values"
    }
  }

  private static func grouped(_ number: Int) -> String {
    let digits = Array(String(number))
    var text = ""

    for (position, digit) in digits.enumerated() {
      if position > 0, (digits.count - position) % 3 == 0 {
        text.append(",")
      }

      text.append(digit)
    }

    return text
  }
}
