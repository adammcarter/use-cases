import Foundation

/// Reads the frames a host sends, and hands the SDK the frame it is to read in its place.
protocol ToolFrameReading: Sendable {
  /// The frame to hand the SDK in place of `frame`.
  func frame(for frame: Data) async -> Data
}
