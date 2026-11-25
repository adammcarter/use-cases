import UseCasesCore

/// The `--json` document of `use-cases verify --abort`: the run it closed and nothing else
/// (`cli-verify.schema.json`).
struct VerifyAbortDocument: Encodable {
  let aborted: AbortedVerifyRun

  /// What there is to say beside the run it closed; left out of the document when empty.
  let notes: [String]

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case step
    case runIdentifier = "run_id"
    case aborted
    case notes
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
      VerifyStep.abort.rawValue,
      forKey: .step,
    )
    try container.encode(
      aborted.runIdentifier,
      forKey: .runIdentifier,
    )
    try container.encode(
      true,
      forKey: .aborted,
    )

    if !notes.isEmpty {
      try container.encode(
        notes,
        forKey: .notes,
      )
    }
  }
}
