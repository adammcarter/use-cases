import Foundation

/// Asks the system whether a descriptor is a terminal.
struct SystemTerminal: TerminalChecking {
  func isTerminal(descriptor: Int32) -> Bool {
    isatty(descriptor) != 0
  }
}
