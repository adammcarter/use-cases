/// Why a batch could not be applied (chapter 16 §14). Every refusal is found before the first
/// byte is written, and one bad change refuses all of the batch.
public enum UseCaseBatchError: Error, Equatable, Sendable {
  /// The input could not be read.
  case input(message: String)

  /// The input is not a mapping of `remove` and `save` with something in it.
  case notABatch(
    name: String,
    problem: String?,
  )

  /// `remove` is not a list of use case ids.
  case removeNotIds(name: String)

  /// `save` is not a list.
  case saveNotUseCases(name: String)

  /// A use case is in the batch more than once.
  case repeated(identifier: String)

  /// The name given with `--approved-by` cannot be recorded.
  case approver(reason: String)

  /// A change of the batch is refused as `save` or `remove` would refuse it.
  case editing(UseCaseEditingError)

  /// A use case could not be signed off.
  case stamping(ApprovalStampingError)

  /// How a script is told about the refusal (chapter 16 §5).
  public var kind: UseCaseEditingError.Kind {
    switch self {
    case .input, .notABatch, .removeNotIds, .saveNotUseCases, .repeated, .approver:
      .usage
    case let .editing(error):
      error.kind
    case .stamping:
      .refused
    }
  }

  /// The refusal as the text a person reads.
  public var message: String {
    switch self {
    case let .input(message), let .approver(message):
      message
    case let .notABatch(name, problem):
      notABatchMessage(
        name: name,
        problem: problem,
      )
    case let .removeNotIds(name):
      "\(name): `remove` lists use case ids, such as shop.share.email"
    case let .saveNotUseCases(name):
      "\(name): `save` lists whole use cases, each a mapping whose `id` is its full id"
    case let .repeated(identifier):
      "'\(identifier)' is in the batch more than once: a use case is in a batch at most once "
        + "(removing and saving one is an update, which is a save)"
    case let .editing(error):
      error.message
    case let .stamping(error):
      error.message
    }
  }

  private func notABatchMessage(
    name: String,
    problem: String?,
  ) -> String {
    let rule = "\(name) is not a batch: a batch is a mapping of `remove` (use case ids) and "
      + "`save` (whole use cases), with something in at least one of them"

    guard let problem else {
      return rule
    }

    return "\(rule); \(problem)"
  }
}
