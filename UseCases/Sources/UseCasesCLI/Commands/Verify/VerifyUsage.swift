/// A command line of `verify` that cannot be a request (chapter 16 §5 "usage").
enum VerifyUsage: Error, Equatable {
  case noStep
  case severalSteps([String])
  case onlyBelongsToStart
  case runIdentifierBelongsToFinish

  var message: String {
    switch self {
    case .noStep:
      "verify: say which step: `--start`, then your tests, then `--finish`; or `--run` to do "
        + "all three; `--abort` closes a started run nobody will finish"
    case let .severalSteps(flags):
      "verify takes one step at a time, not \(flags.joined(separator: " and "))"
    case .onlyBelongsToStart:
      "--only belongs on `use-cases verify --start` or `--run`; a started run keeps what it "
        + "selected"
    case .runIdentifierBelongsToFinish:
      "--run-id belongs on `use-cases verify --finish` or `--abort`"
    }
  }
}
