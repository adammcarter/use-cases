import UseCasesCore

/// The `--json` document of `use-cases validate` for a valid workspace
/// (`cli-validate.schema.json`).
struct ValidateDocument: Encodable {
  let summary: WorkspaceSummary
  let linkCount: Int
  let warnings: [String]

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case valid
    case useCases = "use_cases"
    case ready
    case draft
    case links
    case files
    case warnings
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(
      OutputDocument.version,
      forKey: .outputVersion,
    )
    try container.encode(
      ValidateCommand.name,
      forKey: .command,
    )
    try container.encode(
      true,
      forKey: .valid,
    )
    try container.encode(
      summary.useCases,
      forKey: .useCases,
    )
    try container.encode(
      summary.ready,
      forKey: .ready,
    )
    try container.encode(
      summary.draft,
      forKey: .draft,
    )
    try container.encode(
      linkCount,
      forKey: .links,
    )
    try container.encode(
      summary.files,
      forKey: .files,
    )
    try container.encode(
      warnings,
      forKey: .warnings,
    )
  }
}
