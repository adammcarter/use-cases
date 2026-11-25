/// The `--json` document of `use-cases status` (`cli-status.schema.json`). With `--gate` it also
/// holds the gate's answer.
struct StatusDocument: Encodable {
  let useCases: [StatusUseCaseEntry]
  let summary: StatusSummary
  let warnings: [String]

  /// The group `--group` named; absent without it.
  let group: String?
  let gate: StatusGateAnswer?

  /// What the results store holds; absent when it holds no run.
  let store: StatusStoreEntry?

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case useCases = "use_cases"
    case summary
    case warnings
    case group
    case gate
    case store
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(
      OutputDocument.version,
      forKey: .outputVersion,
    )
    try container.encode(
      StatusCommand.name,
      forKey: .command,
    )
    try container.encode(
      useCases,
      forKey: .useCases,
    )
    try container.encode(
      summary,
      forKey: .summary,
    )
    try container.encode(
      warnings,
      forKey: .warnings,
    )
    try container.encodeIfPresent(
      group,
      forKey: .group,
    )
    try container.encodeIfPresent(
      gate,
      forKey: .gate,
    )
    try container.encodeIfPresent(
      store,
      forKey: .store,
    )
  }
}
