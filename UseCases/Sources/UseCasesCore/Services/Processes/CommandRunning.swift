/// Runs one program to its end and brings back how it ended and what it printed: the process
/// supervisor of chapter 14 for a caller that wants stdout and stderr apart and whole, and
/// wants no time limit.
public protocol CommandRunning: Sendable {
  /// Starts the program directly, in a session and process group of its own, with its output in
  /// files, and watches it until it ends. Cancelling the calling task stops the whole group
  /// (SIGTERM, a grace, then SIGKILL) and answers ``CommandEnding/cancelled``; a task already
  /// cancelled starts nothing. A program that ends badly is an outcome; only one that cannot be
  /// run at all throws.
  func run(_ invocation: CommandInvocation) async throws(CommandRunningError) -> CommandOutcome
}
