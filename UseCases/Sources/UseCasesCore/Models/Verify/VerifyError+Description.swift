public extension VerifyError {
  /// The refusal as the text a person reads.
  var message: String {
    switch self {
    case let .unknownValidations(names, known):
      "--only names unknown validations: \(names.joined(separator: ", ")); "
        + "use-cases-bridge.yml has: \(known.isEmpty ? "none" : known.joined(separator: ", "))"
    case .noStartedRun:
      "no started run: run `use-cases verify --start`, then your tests, then "
        + "`use-cases verify --finish`"
    case let .severalStartedRuns(runs):
      "several started runs are open (\(runs.joined(separator: ", "))): name one with --run-id, "
        + "or close one with `use-cases verify --abort --run-id <id>`"
    case .noOpenRun:
      "no open run to abort"
    case let .severalOpenRuns(runs):
      "several runs are open (\(runs.joined(separator: ", "))): name one with --run-id"
    case let .noSuchRun(run):
      "no started run \(run) in this workspace"
    case let .alreadySealed(run):
      "run \(run) is already finished; a finished run cannot be finished or aborted again"
    case let .stoppedBeforeFinishing(run):
      "run \(run) was opened by `use-cases verify --run`, which stopped before finishing it; "
        + "its reports may be half written, so it can only be closed with "
        + "`use-cases verify --abort --run-id \(run)`"
    case let .beingFinished(run):
      "run \(run) is being finished by another process"
    case let .settingsChanged(run):
      "use-cases-bridge.yml changed for this run's validations since `--start`; run "
        + "`use-cases verify --abort --run-id \(run)` and start again, so the settings and the "
        + "reports match"
    case let .stagedResults(run):
      "run \(run) already holds results from a finish that stopped partway; close it with "
        + "`use-cases verify --abort --run-id \(run)`"
    case let .invalidWorkspace(problems):
      problems.joined(separator: "\n")
    case let .storage(message):
      message
    case .cancelled:
      "cancelled"
    }
  }
}
