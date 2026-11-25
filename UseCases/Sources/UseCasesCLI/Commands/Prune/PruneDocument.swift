import UseCasesCore

/// The `--json` document of `use-cases prune` (`cli-prune.schema.json`).
struct PruneDocument: Encodable {
  let report: PruneReport

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case removed
    case leftovers
    case kept
    case leftOver = "left_over"
    case bytes
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
      PruneCommand.name,
      forKey: .command,
    )
    try container.encode(
      report.removed.map(PruneRunEntry.init),
      forKey: .removed,
    )
    try container.encode(
      report.leftovers.map(PruneLeftoverEntry.init),
      forKey: .leftovers,
    )
    try container.encode(
      report.kept.map(PruneRunEntry.init),
      forKey: .kept,
    )
    try container.encode(
      report.leftOver.map(PruneLeftoverEntry.init),
      forKey: .leftOver,
    )
    try container.encode(
      report.bytes,
      forKey: .bytes,
    )
    try container.encode(
      report.notes,
      forKey: .notes,
    )
    try container.encode(
      report.isDryRun,
      forKey: .dryRun,
    )
  }
}
