import Foundation

/// `new Date().toISOString()`.
///
/// Every appending MCP tool stamps its event with the clock unless the caller
/// pins `recorded_at`, which is why the recorded corpus pins it: the clock is
/// the one genuinely nondeterministic input.
public enum McpClock {
  /// The instant now, spelled the way JavaScript spells it: UTC, milliseconds,
  /// a trailing `Z`.
  public static func nowIsoString() -> String {
    isoString(Date())
  }

  static func isoString(_ date: Date) -> String {
    var calendar = Calendar(identifier: .gregorian)
    guard let utc = TimeZone(identifier: "UTC") else {
      return ""
    }
    calendar.timeZone = utc
    let parts = calendar.dateComponents(
      [.year, .month, .day, .hour, .minute, .second, .nanosecond],
      from: date,
    )
    let milliseconds = (parts.nanosecond ?? 0) / 1_000_000
    return String(
      format: "%04d-%02d-%02dT%02d:%02d:%02d.%03dZ",
      parts.year ?? 0,
      parts.month ?? 0,
      parts.day ?? 0,
      parts.hour ?? 0,
      parts.minute ?? 0,
      parts.second ?? 0,
      milliseconds,
    )
  }
}
