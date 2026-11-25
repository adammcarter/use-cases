/// The sealed run a `record` request wrote: its manifest fields and its one result
/// (`cli-record.schema.json`).
public struct RecordedRun: Equatable, Sendable {
  /// The run's id: 32 lowercase hexadecimal digits.
  public let runIdentifier: String

  /// When the run was allocated, UTC RFC 3339.
  public let createdAt: String

  /// The full id of the use case.
  public let useCase: String

  /// The route's id.
  public let route: String

  /// The route's fingerprint when the verdict was recorded.
  public let fingerprint: String

  /// `pass`, `fail`, `incomplete` or `error`.
  public let status: String

  /// When the verdict was recorded, UTC RFC 3339.
  public let recordedAt: String

  /// The note that went with the verdict.
  public let message: String?

  /// The files kept with the verdict, in the order they were given.
  public let attachments: [RecordedAttachment]

  /// Makes the description of a recorded run.
  public init(
    runIdentifier: String,
    createdAt: String,
    useCase: String,
    route: String,
    fingerprint: String,
    status: String,
    recordedAt: String,
    message: String?,
    attachments: [RecordedAttachment],
  ) {
    self.runIdentifier = runIdentifier
    self.createdAt = createdAt
    self.useCase = useCase
    self.route = route
    self.fingerprint = fingerprint
    self.status = status
    self.recordedAt = recordedAt
    self.message = message
    self.attachments = attachments
  }
}
