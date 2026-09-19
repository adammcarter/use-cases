import Foundation

/// The two string orders the TypeScript matrix code sorts by, kept apart
/// because they disagree and each call site uses exactly one of them.
///
/// `localeCompare` is ICU collation: punctuation before digits before letters,
/// `_` before `-` before `.`, lowercase before uppercase, accents after the base
/// letter. A bare `.sort()` compares UTF-16 code units: `-` < `.` < digits <
/// uppercase < `_` < lowercase. Both are used together in
/// `buildMatrixSnapshot`, four lines apart.
enum JavaScriptStringOrder {
  /// `left.localeCompare(right) < 0`, the comparator
  /// `(a, b) => a.localeCompare(b)` hands `Array.prototype.sort`. The same
  /// comparison ``CanonicalJSON`` sorts object keys with.
  static func localeAscending(
    _ left: String,
    _ right: String,
  ) -> Bool {
    left.compare(right, options: [], range: nil, locale: locale) == .orderedAscending
  }

  /// `.sort()` with no comparator: UTF-16 code-unit order.
  static func codeUnitAscending(
    _ left: String,
    _ right: String,
  ) -> Bool {
    left.utf16.lexicographicallyPrecedes(right.utf16)
  }

  /// libuv's `scandir` order, which is what `readdirSync` returns before the
  /// TypeScript re-sorts it: `strcmp` over the UTF-8 bytes of each name. It
  /// decides the order of names `localeCompare` calls equal.
  static func byteAscending(
    _ left: String,
    _ right: String,
  ) -> Bool {
    left.utf8.lexicographicallyPrecedes(right.utf8)
  }

  private static let locale = Locale(identifier: "en_US")
}
