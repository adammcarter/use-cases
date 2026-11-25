/// An integer a YAML scalar spells, or the fact that it does not fit in an `Int`.
enum YAMLInteger: Equatable, Sendable {
  case exact(Int)
  case tooLarge

  /// Reads digits in a radix. Underscores (YAML 1.1 spelling) and leading zeros are ignored.
  init(
    digits: Substring,
    radix: Int,
    isNegative: Bool,
  ) {
    let significant = digits.filter { $0 != "_" }.drop { $0 == "0" }

    guard !significant.isEmpty else {
      self = .exact(0)
      return
    }

    let signed = (isNegative ? "-" : "") + significant

    if let value = Int(signed, radix: radix) {
      self = .exact(value)
    } else {
      self = .tooLarge
    }
  }
}
