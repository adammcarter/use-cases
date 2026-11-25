/// Why a command could not be supervised at all (as against ending badly, which a
/// `ProcessTermination` says).
enum ProcessSupervisingError: Error, Equatable {
  /// The command could not be started: not found, not executable, no such working folder.
  case couldNotLaunch(reason: String)

  /// The scratch file that holds the command's output could not be made or read.
  case captureUnavailable(reason: String)

  /// The system could not say how the command ended.
  case waitFailed(reason: String)
}
