/// Where a command's stdout and stderr go, and what is kept of them (chapter 14 §10).
protocol ConsoleCapturing: Sendable {
  /// An open descriptor the command's output is written to.
  var descriptor: Int32 { get }

  /// What was written, bounded to 1 MiB.
  func read() throws(ProcessSupervisingError) -> ProcessConsole

  /// Lets go of the capture.
  func release()
}
