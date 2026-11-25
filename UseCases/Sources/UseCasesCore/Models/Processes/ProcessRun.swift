/// What supervising one command produced: how it ended and what it printed.
struct ProcessRun: Equatable, Sendable {
  let termination: ProcessTermination

  /// Bounded to 1 MiB (chapter 14 §10). Kept for every ending, a timeout and a cancellation
  /// included.
  let console: ProcessConsole

  /// Whether the command was started. A request cancelled before the command started never ran
  /// it, so it has nothing to show; one cancelled after, however quiet the command was, ran it.
  let wasLaunched: Bool
}
