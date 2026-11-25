@testable import UseCasesCore

/// A capture that holds nothing.
struct MockConsoleCapture: ConsoleCapturing {
  let descriptor: Int32 = -1

  func read() -> ProcessConsole {
    .empty
  }

  func release() {
    // Nothing to let go of.
  }
}
