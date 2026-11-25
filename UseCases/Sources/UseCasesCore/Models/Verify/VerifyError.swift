/// Why a `verify` step was refused (chapter 13 §4, §6, chapter 16 §5). Nothing was sealed when
/// one is thrown, and a run that was open stays open.
public enum VerifyError: Error, Equatable, Sendable {
  /// `--only` names validations the bridge settings do not have.
  case unknownValidations(
    [String],
    known: [String],
  )

  /// `--finish` found no run that `--start` left open.
  case noStartedRun

  /// `--finish` found several runs that `--start` left open and was not told which.
  case severalStartedRuns([String])

  /// `--abort` found no open run.
  case noOpenRun

  /// `--abort` found several open runs and was not told which.
  case severalOpenRuns([String])

  /// `--run-id` names a run that is not in the store, or is not a verify run.
  case noSuchRun(String)

  /// `--run-id` names a run that is sealed.
  case alreadySealed(String)

  /// `--finish` was told a run that `verify --run` opened. Its reports may be half written and its
  /// exit codes are lost, so it can only be aborted (chapter 13 §6).
  case stoppedBeforeFinishing(String)

  /// Another process holds the run's lock (chapter 12 §18).
  case beingFinished(String)

  /// The validations of `use-cases-bridge.yml` are not what the run's start point recorded.
  case settingsChanged(run: String)

  /// The run's log already holds results, which a finish that stopped partway left behind.
  case stagedResults(run: String)

  /// The workspace is INVALID. Each problem is one line.
  case invalidWorkspace(problems: [String])

  /// The results store cannot be read or written safely.
  case storage(String)

  /// The request was cancelled before there was anything to seal.
  case cancelled
}
