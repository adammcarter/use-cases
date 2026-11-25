/// Says whether the run has been cancelled (chapter 14 §14). The supervisor asks between its
/// steps; it never waits to be told.
///
/// Public so that the test support target can offer a double of it.
public protocol CancellationObserving: Sendable {
  func isCancelled() async -> Bool
}
