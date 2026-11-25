import Foundation

extension Date {
  /// The time as the store writes it: UTC RFC 3339 with milliseconds and a `Z`, such as
  /// `2026-09-25T12:34:56.123Z` (chapter 12 §13).
  var storeTimestamp: String {
    formatted(Date.ISO8601FormatStyle(includingFractionalSeconds: true))
  }

  /// Whole milliseconds since 1970; zero for a time before it.
  var storeMilliseconds: UInt64 {
    UInt64(exactly: (timeIntervalSince1970 * 1000).rounded(.down)) ?? 0
  }
}
