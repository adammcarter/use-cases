import Foundation

/// Writes frames to the host one at a time, each to its end before the next begins.
protocol FrameWriting: Actor {
  /// Writes `frame` once every frame asked for before it has been written, and returns when it
  /// has been, or throws why it could not be.
  func write(_ frame: Data) async throws
}
