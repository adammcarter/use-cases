/// What became of one use case `approve` was asked to sign off (chapter 16 §14).
public struct ApprovedUseCase: Equatable, Sendable {
  /// The full id of the use case.
  public let identifier: String

  /// The definition file it is in, relative to the workspace root.
  public let file: String

  public let action: ApprovalAction
}
