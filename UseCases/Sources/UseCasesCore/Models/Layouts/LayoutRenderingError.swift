/// Why a layout could not be drawn (chapter 21 §7). Every refusal is found before anything is
/// drawn, and nothing is written.
public enum LayoutRenderingError: Error, Equatable, Sendable {
  /// The input could not be read.
  case input(message: String)

  /// The input is not an intent: `what` and `why`, and optionally `who`.
  case invalidIntent(name: String)

  /// A text field holds a character a terminal would act on.
  case controlCharacter(
    name: String,
    field: String,
    character: Unicode.Scalar,
  )

  /// The input is not a proposal; `problem` says what is wrong with it.
  case invalidProposal(
    name: String,
    problem: String,
  )

  /// The batch inside the proposal is refused as `apply` refuses a batch.
  case batch(UseCaseBatchError)

  /// The proposal names a use case the workspace does not have.
  case unknownUseCase(identifier: String)

  /// The proposal has not been applied, so there are no results to draw.
  case notApplied(identifier: String)

  /// The promise of a use case could not be fingerprinted, so whether it was applied is unknown.
  case unfingerprintable(
    identifier: String,
    reason: String,
  )

  /// The workspace could not be judged for the results.
  case status(StatusJudgingError)

  /// How a script is told about the refusal (chapter 16 §5).
  public var kind: UseCaseEditingError.Kind {
    switch self {
    case .input, .invalidIntent, .controlCharacter, .invalidProposal, .unknownUseCase:
      .usage
    case let .batch(error):
      error.kind
    case .notApplied, .unfingerprintable, .status:
      .refused
    }
  }

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .input(message):
      message
    case let .invalidIntent(name):
      "\(name.displayEscaped): an intent has `what` and `why` (text), "
        + "and optionally `who` (a list of text)"
    case let .controlCharacter(name, field, character):
      "\(name.displayEscaped): `\(field)` holds the control character "
        + "'\(character.escapedForDisplay)': write it in words"
    case let .invalidProposal(name, problem):
      "\(name.displayEscaped): \(problem)"
    case let .batch(error):
      error.message
    case let .unknownUseCase(identifier):
      "no use case '\(identifier.displayEscaped)' in this workspace; "
        + "a proposal names use cases by their full id"
    case let .notApplied(identifier):
      "'\(identifier.displayEscaped)' is not as the proposal leaves it: "
        + "apply the proposal before its results"
    case let .unfingerprintable(identifier, reason):
      "the promise of \(identifier.displayEscaped) could not be fingerprinted: \(reason)"
    case let .status(error):
      error.message
    }
  }
}
