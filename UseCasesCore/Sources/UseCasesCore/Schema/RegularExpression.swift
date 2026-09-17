/// The `pattern` keyword. Patterns are written in ECMAScript syntax and are
/// tested the way `RegExp.prototype.test` tests them: an unanchored pattern may
/// match anywhere, and `$` means the END of the string.
///
/// Swift's own engine is used rather than `NSRegularExpression` for exactly that
/// last reason — ICU lets `$` match before a trailing newline, so an id ending in
/// one would be accepted here and refused in TypeScript. Regexes are built per
/// call because `Regex` is not `Sendable` and may not be cached in a static.
enum RegularExpression {
  static func matches(
    _ text: String,
    _ pattern: String,
  ) -> Bool {
    guard let expression = try? Regex(pattern).matchingSemantics(.unicodeScalar) else {
      return false
    }
    return text.firstMatch(of: expression) != nil
  }
}
