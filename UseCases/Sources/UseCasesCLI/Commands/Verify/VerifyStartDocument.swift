import UseCasesCore

/// The `--json` document of `use-cases verify --start` (`cli-verify.schema.json`).
struct VerifyStartDocument: Encodable {
  let started: StartedVerifyRun

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case step
    case started
    case runIdentifier = "run_id"
    case selected
    case reports
    case notes
  }

  /// Where each validation's report goes, by validation id.
  private var reportPaths: [String: String] {
    var paths: [String: String] = [:]

    for report in started.reports {
      paths[report.validation] = report.path
    }

    return paths
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(
      OutputDocument.version,
      forKey: .outputVersion,
    )
    try container.encode(
      VerifyCommand.name,
      forKey: .command,
    )
    try container.encode(
      VerifyStep.start.rawValue,
      forKey: .step,
    )
    try container.encode(
      started.isStarted,
      forKey: .started,
    )

    if let identifier = started.runIdentifier {
      try container.encode(
        identifier,
        forKey: .runIdentifier,
      )
      try container.encode(
        started.selected,
        forKey: .selected,
      )
      try container.encode(
        reportPaths,
        forKey: .reports,
      )
    }

    try container.encode(
      started.notes,
      forKey: .notes,
    )
  }
}
