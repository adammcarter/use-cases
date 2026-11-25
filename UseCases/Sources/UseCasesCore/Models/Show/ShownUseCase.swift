/// One use case, whole, as `show` tells it (chapter 16 §14).
public struct ShownUseCase: Equatable, Sendable {
  /// The full id.
  public let identifier: String

  /// The definition file it is written in, relative to the workspace root.
  public let file: String

  /// Whether it is fully written: READY, or DRAFT.
  public let isReady: Bool

  /// What a DRAFT lacks before it is READY; empty for a READY use case.
  public let missing: [String]

  /// Whether its promise is signed off as it reads now.
  public let approval: ApprovalState

  /// The use case as `save` takes it: every field as authored, with its full id.
  public let definition: StoreJSONValue

  /// The same, as the YAML lines `save` would write.
  public let yamlLines: [String]

  /// A use case, shown.
  public init(
    identifier: String,
    file: String,
    isReady: Bool,
    missing: [String],
    approval: ApprovalState,
    definition: StoreJSONValue,
    yamlLines: [String],
  ) {
    self.identifier = identifier
    self.file = file
    self.isReady = isReady
    self.missing = missing
    self.approval = approval
    self.definition = definition
    self.yamlLines = yamlLines
  }
}
