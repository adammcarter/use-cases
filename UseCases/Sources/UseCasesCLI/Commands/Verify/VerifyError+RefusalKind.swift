import UseCasesCore

extension VerifyError {
  /// How a refusal to verify is told to a script (chapter 16 §5); `nil` for a cancellation, which
  /// is not a refusal.
  var refusalKind: RefusalKind? {
    switch self {
    case .unknownValidations:
      .usage
    case .noStartedRun, .severalStartedRuns, .noOpenRun, .severalOpenRuns, .noSuchRun,
         .alreadySealed, .stoppedBeforeFinishing, .beingFinished, .settingsChanged,
         .stagedResults:
      .refused
    case .invalidWorkspace:
      .invalid
    case .storage:
      .storage
    case .cancelled:
      nil
    }
  }
}
