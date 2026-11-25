import Foundation
@testable import UseCasesMCP

/// A reader that hands the SDK the same frame whatever the host sent.
struct StubToolFrameReading: ToolFrameReading {
  let standIn: Data

  func frame(for _: Data) async -> Data {
    standIn
  }
}
