import UseCasesCore

/// The one result in the record document, in the shape of a line of the run's log.
struct RecordResultEntry: Encodable {
  let useCase: String
  let route: String
  let fingerprint: String
  let status: String
  let recordedAt: String

  /// Absent when the verdict has no note, never `null`.
  let message: String?

  /// Absent when nothing was attached, never an empty list.
  let attachments: [RecordAttachmentEntry]

  enum CodingKeys: String, CodingKey {
    case recordVersion = "record_version"
    case useCase = "use_case"
    case route
    case fingerprint
    case status
    case via
    case recordedAt = "recorded_at"
    case message
    case attachments
  }

  init(_ run: RecordedRun) {
    useCase = run.useCase
    route = run.route
    fingerprint = run.fingerprint
    status = run.status
    recordedAt = run.recordedAt
    message = run.message
    attachments = run.attachments.map(RecordAttachmentEntry.init)
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(
      1,
      forKey: .recordVersion,
    )
    try container.encode(
      useCase,
      forKey: .useCase,
    )
    try container.encode(
      route,
      forKey: .route,
    )
    try container.encode(
      fingerprint,
      forKey: .fingerprint,
    )
    try container.encode(
      status,
      forKey: .status,
    )
    try container.encode(
      ["record"],
      forKey: .via,
    )
    try container.encode(
      recordedAt,
      forKey: .recordedAt,
    )
    try container.encodeIfPresent(
      message,
      forKey: .message,
    )

    if !attachments.isEmpty {
      try container.encode(
        attachments,
        forKey: .attachments,
      )
    }
  }
}
