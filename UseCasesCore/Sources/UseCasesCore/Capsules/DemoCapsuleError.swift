/// Why loading, planning or running a capsule stopped with an error rather
/// than a result. Each case is an error the TypeScript lets escape.
public enum DemoCapsuleError: Error, Equatable, Sendable {
  /// A directory could not be listed, an entry inspected or a file read.
  case fileAccess(FileAccessError)
  /// Loading the use-case matrix failed.
  case matrix(UseCaseMatrixError)
  /// Replaying the evidence ledger failed.
  case evidence(EvidenceEventError)
  /// Planning the presentation failed.
  case presentation(PresentationError)
  /// Recording to the showcase run failed.
  case showcase(ShowcaseError)
  /// `spawnSync` refused a command step.
  case spawn(CapsuleSpawnError)

  public var code: String {
    switch self {
    case let .fileAccess(error): error.code
    case let .matrix(error): error.code
    case let .evidence(error): error.code
    case let .presentation(error): error.code
    case let .showcase(error): error.code
    case let .spawn(error): error.code
    }
  }

  public var message: String {
    switch self {
    case let .fileAccess(error): error.message
    case let .matrix(error): error.message
    case let .evidence(error): error.message
    case let .presentation(error): error.message
    case let .showcase(error): error.message
    case let .spawn(error): error.message
    }
  }
}
