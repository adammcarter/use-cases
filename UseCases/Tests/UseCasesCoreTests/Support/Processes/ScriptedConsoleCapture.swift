@testable import UseCasesCore

/// A capture that holds what the test gave it, and nothing a command wrote.
struct ScriptedConsoleCapture: ConsoleCapturing {
  let console: ProcessConsole

  let descriptor: Int32 = -1

  func read() -> ProcessConsole {
    console
  }

  func release() {
    // Nothing to let go of.
  }
}
