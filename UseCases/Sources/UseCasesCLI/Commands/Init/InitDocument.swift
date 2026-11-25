import UseCasesCore

/// The `--json` document of `use-cases init` (`cli-init.schema.json`).
struct InitDocument: Encodable {
  let workspace: String
  let created: [String]
  let kept: [String]
  let hooks: [String]
  let gitignore: GitignoreOutcome
  let notes: [String]
  let dryRun: Bool

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case workspace
    case created
    case kept
    case gitignore
    case hooks
    case notes
    case dryRun = "dry_run"
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(
      OutputDocument.version,
      forKey: .outputVersion,
    )
    try container.encode(
      InitCommand.name,
      forKey: .command,
    )
    try container.encode(
      workspace,
      forKey: .workspace,
    )
    try container.encode(
      created,
      forKey: .created,
    )
    try container.encode(
      kept,
      forKey: .kept,
    )
    try container.encode(
      gitignore.rawValue,
      forKey: .gitignore,
    )
    try container.encode(
      hooks,
      forKey: .hooks,
    )
    try container.encode(
      notes,
      forKey: .notes,
    )
    try container.encode(
      dryRun,
      forKey: .dryRun,
    )
  }
}
