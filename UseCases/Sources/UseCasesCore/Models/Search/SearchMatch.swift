/// One use case that matched a search.
public struct SearchMatch: Equatable, Sendable {
  /// The full id.
  public let identifier: String

  public let title: String

  /// The definition file, relative to the workspace root.
  public let file: String

  /// The state `status` lists it in.
  public let status: VerificationStatus

  /// `critical`, `core` or `supporting`; `nil` when the use case has not chosen one.
  public let valueTier: String?

  /// From 0.0001 to 1, in ten-thousandths. It orders the results of one search and means nothing
  /// beside another search's.
  public let score: Double

  /// Every place it matched, the strongest first; never empty.
  public let reasons: [SearchReason]

  /// The whole use case, exactly as `show` returns it; only when `--full` asked.
  public let definition: StoreJSONValue?

  /// A match.
  public init(
    identifier: String,
    title: String,
    file: String,
    status: VerificationStatus,
    valueTier: String?,
    score: Double,
    reasons: [SearchReason],
    definition: StoreJSONValue?,
  ) {
    self.identifier = identifier
    self.title = title
    self.file = file
    self.status = status
    self.valueTier = valueTier
    self.score = score
    self.reasons = reasons
    self.definition = definition
  }
}
