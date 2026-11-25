import Foundation
@testable import UseCasesMCP

/// A writer that writes nowhere: it keeps the frames it is asked to write, and fails each when
/// told to.
actor SpyFrameWriting: FrameWriting {
  struct Failure: Error {}

  /// The frames asked for, in order.
  private(set) var frames: [Data] = []

  private let isFailing: Bool

  init(failing isFailing: Bool = false) {
    self.isFailing = isFailing
  }

  func write(_ frame: Data) async throws {
    frames.append(frame)

    if isFailing {
      throw Failure()
    }
  }
}
