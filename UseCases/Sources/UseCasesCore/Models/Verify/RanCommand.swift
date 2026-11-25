/// What `verify --run` knows about the command it ran for one validation (chapter 13 §7). A
/// report the person's own tests wrote has none.
struct RanCommand: Equatable, Sendable {
  /// What `verify --run` says of a validation that has no run command (chapter 13 §7 step 2a).
  static let missingWords =
    "no run command: run its tests yourself between `use-cases verify --start` and "
      + "`use-cases verify --finish`"

  /// The validation had no run command, so there was nothing to run.
  static let missing = RanCommand(
    command: nil,
    failure: missingWords,
    exitCode: nil,
    seconds: nil,
  )

  /// The run command as the bridge settings wrote it; `nil` when there was none.
  let command: [String]?

  /// Why the command could not run at all: it could not be launched, it timed out, a signal killed
  /// it (chapter 13 §10). `nil` when it ended by itself.
  let failure: String?

  /// Its exit code; `nil` when it did not end by itself.
  let exitCode: Int32?

  /// How long it ran; `nil` when it never ran.
  let seconds: Double?
}
