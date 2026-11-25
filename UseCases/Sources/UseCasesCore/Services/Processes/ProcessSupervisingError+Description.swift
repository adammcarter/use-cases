extension ProcessSupervisingError: CustomStringConvertible {
  /// The run error, in the words of chapter 14 §7 and the acceptance suite.
  var description: String {
    switch self {
    case let .couldNotLaunch(reason):
      "command could not be launched: \(reason)"
    case let .captureUnavailable(reason):
      "the command's output could not be captured: \(reason)"
    case let .waitFailed(reason):
      "the command could not be waited for: \(reason)"
    }
  }
}
