extension TransformerError: CustomStringConvertible {
  /// The error in the words of chapter 10 §14 and the acceptance suite; it always starts with the
  /// transformer's name, except for a cancellation.
  var description: String {
    switch self {
    case let .programMissing(name, expectedAt):
      "\(name) could not be launched: the bundled transformers program is not there; looked for "
        + expectedAt
    case let .couldNotLaunch(name, reason):
      "\(name) could not be launched: \(reason)"
    case let .scratchUnavailable(name, reason):
      "\(name) could not be run: the private folder for its request and response is "
        + "unavailable: \(reason)"
    case let .timedOut(name, duration):
      "\(name) did not finish within \(duration.components.seconds) seconds"
    case let .signaled(name, signal):
      "\(name) was terminated abnormally (signal \(signal))"
    case let .exited(name, code, console):
      console.isEmpty ? "\(name) exited \(code)" : "\(name) exited \(code): \(console)"
    case let .malformedResponse(name, reason):
      "\(name) wrote malformed output: \(reason)"
    case let .unsupportedContract(name):
      "\(name) did not answer with contract 1"
    case let .badLink(name, link, problem):
      "\(name) returned a bad link \(link): \(problem)"
    case let .unknownResultLink(name, link):
      "\(name) reported a result for \(link), which does not exist among the validation links "
        + "of this run"
    case let .invalidResultStatus(name, link, status):
      "\(name) reported the status '\(status)' for \(link); a status is pass, fail, error or "
        + "incomplete"
    case .cancelled:
      "cancelled"
    }
  }
}
