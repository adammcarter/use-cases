import Foundation

/// Starts a command (chapter 14 §6 to §9).
protocol ProcessLaunching: Sendable {
  /// Starts the command, with its output going to `capture`, and returns its process ID, which
  /// is also the ID of its process group.
  func launch(
    arguments: [String],
    workingDirectory: URL,
    capture: any ConsoleCapturing,
  ) throws(ProcessSupervisingError) -> pid_t
}
