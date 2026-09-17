import Foundation

/// The source of `new Date()`, which dates the AGENTS.md decision when no day
/// is given.
public protocol InitializationClock: Sendable {
  /// Milliseconds since the epoch, as `Date.now()` answers.
  func now() -> Double
}

/// The process's own clock.
public struct SystemInitializationClock: InitializationClock {
  /// Reads the system time.
  public init() {}

  public func now() -> Double {
    (Date().timeIntervalSince1970 * 1000).rounded(.down)
  }
}

extension InitializationClock {
  /// `new Date().toISOString().slice(0, 10)`.
  var today: String {
    CodeUnits.string(Array(JavaScriptTimestamp.isoString(milliseconds: now()).utf16).prefix(10))
  }
}
