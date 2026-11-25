/// How a program the test started ended.
struct ProcessTermination: Sendable, Equatable {
  /// Whether it ended by exiting, and not by a signal.
  let isExit: Bool

  /// Its exit code, or the signal that ended it.
  let status: Int32
}
