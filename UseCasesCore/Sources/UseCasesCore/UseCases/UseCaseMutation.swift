/// Which change a mutation makes.
public enum UseCaseMutationOperation: String, Sendable, Equatable {
  case upsert
  case remove
}

/// What a mutation did. The raw values are frozen wire contract
/// (`matrix-mutation-result.schema.json`).
public enum UseCaseMutationStatus: String, Sendable, Equatable {
  case created
  case updated
  case removed
  case blocked
}

/// A requested change to one row.
///
/// Every string is optional and an EMPTY one counts as absent wherever the
/// TypeScript tests it for truthiness (`targetFile`, `useCaseIdentifier`,
/// `reason`, `expectedSemanticHash`). `actor` is only defaulted when nil.
public struct UseCaseMutationOptions: Sendable, Equatable {
  public var context: ResolvedWorkspaceContext
  public var operation: UseCaseMutationOperation

  /// Upsert: the file to write, relative to the use-cases root, optionally
  /// prefixed `use-cases/`.
  public var targetFile: String?

  /// Remove: the row to retire.
  public var useCaseIdentifier: String?

  /// Upsert: the whole row, in the caller's key order.
  public var useCase: JSONObject?

  /// When non-empty, the existing row's hash must equal it.
  public var expectedSemanticHash: String?

  /// Remove: why the row is retired.
  public var reason: String?

  /// Remove: who retired it; `agent` when nil.
  public var actor: String?

  public init(
    context: ResolvedWorkspaceContext,
    operation: UseCaseMutationOperation,
    targetFile: String? = nil,
    useCaseIdentifier: String? = nil,
    useCase: JSONObject? = nil,
    expectedSemanticHash: String? = nil,
    reason: String? = nil,
    actor: String? = nil,
  ) {
    self.context = context
    self.operation = operation
    self.targetFile = targetFile
    self.useCaseIdentifier = useCaseIdentifier
    self.useCase = useCase
    self.expectedSemanticHash = expectedSemanticHash
    self.reason = reason
    self.actor = actor
  }
}

/// The outcome of a mutation.
public struct UseCaseMutationResult: Sendable, Equatable {
  public let operation: UseCaseMutationOperation
  public let status: UseCaseMutationStatus
  public let useCaseIdentifier: String?
  public let filePath: String?
  public let beforeHash: String?
  public let afterHash: String?
  public let diagnostics: [Diagnostic]

  /// The wire form, in the frozen key order.
  public var jsonValue: JSONValue {
    func optional(_ text: String?) -> JSONValue {
      text.map(JSONValue.string) ?? .null
    }
    return .object(JSONObject([
      ("schema_version", .number(1)),
      ("operation", .string(operation.rawValue)),
      ("status", .string(status.rawValue)),
      ("use_case_id", optional(useCaseIdentifier)),
      ("file_path", optional(filePath)),
      ("before_hash", optional(beforeHash)),
      ("after_hash", optional(afterHash)),
      ("diagnostics", .array(diagnostics.map(\.jsonValue))),
    ]))
  }
}
