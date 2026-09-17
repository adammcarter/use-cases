/// What stops a marker command core from producing a result at all: each is a
/// throw in the TypeScript, never a result with an exit code.
public enum MarkerCommandError: Error, Equatable, Sendable {
  /// A source file, ledger or directory could not be read or written for a
  /// reason other than it being absent.
  case fileAccess(FileAccessError)
  /// The use-case matrix could not be walked.
  case useCaseMatrix(UseCaseMatrixError)
  /// The base-ref version of a ledger could not be read.
  case git(GitError)
  /// A proof event could not be checked at all.
  case evidenceLedger(EvidenceLedgerError)
  /// A chained ledger entry carries a number JSON cannot spell.
  case canonicalJSON(CodeUnitCanonicalJSONError)

  public var code: String {
    switch self {
    case let .fileAccess(error): error.code
    case let .useCaseMatrix(error): error.code
    case let .git(error): error.code
    case let .evidenceLedger(error): error.code
    case .canonicalJSON: "canonical_json_non_finite"
    }
  }

  public var message: String {
    switch self {
    case let .fileAccess(error): error.message
    case let .useCaseMatrix(error): error.message
    case let .git(error): error.message
    case let .evidenceLedger(error): error.message
    case let .canonicalJSON(error): error.message
    }
  }
}

/// One `{ code, message }` a command result or a marker edit reports.
public struct MarkerCommandFailure: Equatable, Sendable {
  public let code: String
  public let message: String

  public init(
    code: String,
    message: String,
  ) {
    self.code = code
    self.message = message
  }

  var jsonValue: JSONValue {
    .object(JSONObject([("code", .string(code)), ("message", .string(message))]))
  }
}
