import Foundation

/// `String.prototype.localeCompare`, which is how the binding resource orders
/// its rows and slugs: punctuation before letters, lowercase before uppercase.
///
/// Swift's own `<` is close for lowercase ASCII ids but not the same rule, and
/// the ordering is on the wire.
enum McpLocaleOrder {
  static func isAscending(
    _ left: String,
    _ right: String,
  ) -> Bool {
    left.compare(
      right,
      options: [],
      range: nil,
      locale: Locale(identifier: "en_US"),
    ) == .orderedAscending
  }
}
