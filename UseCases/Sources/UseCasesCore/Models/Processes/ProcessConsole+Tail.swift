import Foundation

extension ProcessConsole {
  /// The end of what was printed, for a message: trimmed, and cut to its last `limit`
  /// characters.
  func tail(limit: Int) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    guard trimmed.count > limit else {
      return trimmed
    }

    return String(trimmed.suffix(limit))
  }
}
