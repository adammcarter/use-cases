import Foundation

/// Asks whether a child has ended, without waiting for it.
protocol ProcessReaping: Sendable {
  /// How the child ended, or `nil` while it still runs. Collects the child once it has ended, so
  /// each child is answered once. (Asynchronous so that a double which keeps count of the calls
  /// can be an actor.)
  func poll(_ processIdentifier: pid_t) async throws(ProcessSupervisingError) -> ProcessTermination?
}
