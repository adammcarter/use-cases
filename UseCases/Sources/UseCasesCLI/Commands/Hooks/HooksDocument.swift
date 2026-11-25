import UseCasesCore

/// The `--json` document of `use-cases hooks` (`cli-hooks.schema.json`).
struct HooksDocument: Encodable {
  let plan: HooksPlan
  let notes: [String]
  let isDryRun: Bool

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case hooksDirectory = "hooks_dir"
    case managed
    case hooks
    case changed
    case notes
    case dryRun = "dry_run"
  }

  /// One hook as the document lists it.
  private struct Entry: Encodable {
    let name: String
    let event: String
    let state: String
    let runs: String
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(
      OutputDocument.version,
      forKey: .outputVersion,
    )
    try container.encode(
      HooksCommand.name,
      forKey: .command,
    )
    try container.encode(
      plan.hooksFolder,
      forKey: .hooksDirectory,
    )
    try container.encode(
      plan.isManaged,
      forKey: .managed,
    )
    try container.encode(
      plan.hooks.map { hook in
        Entry(
          name: hook.name.rawValue,
          event: hook.name.event,
          state: hook.state.rawValue,
          runs: hook.name.runs,
        )
      },
      forKey: .hooks,
    )
    try container.encode(
      plan.changed.map(\.rawValue),
      forKey: .changed,
    )
    try container.encode(
      plan.notes + notes,
      forKey: .notes,
    )
    try container.encode(
      isDryRun,
      forKey: .dryRun,
    )
  }
}
