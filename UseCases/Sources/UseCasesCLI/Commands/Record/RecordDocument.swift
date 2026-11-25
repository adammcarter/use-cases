import UseCasesCore

/// The `--json` document of `use-cases record` (`cli-record.schema.json`): the manifest fields of
/// the sealed record run and its one result.
struct RecordDocument: Encodable {
  let run: RecordedRun
  let notes: [String]

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case runVersion = "run_version"
    case runIdentifier = "run_id"
    case createdAt = "created_at"
    case kind
    case sources
    case errors
    case diagnostics
    case unlinkedTests = "unlinked_tests"
    case notes
    case results
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(
      OutputDocument.version,
      forKey: .outputVersion,
    )
    try container.encode(
      RecordCommand.name,
      forKey: .command,
    )
    try container.encode(
      1,
      forKey: .runVersion,
    )
    try container.encode(
      run.runIdentifier,
      forKey: .runIdentifier,
    )
    try container.encode(
      run.createdAt,
      forKey: .createdAt,
    )
    try container.encode(
      "record",
      forKey: .kind,
    )

    // A record run has no validations, so none of these has anything in it.
    try container.encode(
      [String](),
      forKey: .sources,
    )
    try container.encode(
      [String](),
      forKey: .errors,
    )
    try container.encode(
      [String](),
      forKey: .diagnostics,
    )
    try container.encode(
      [String](),
      forKey: .unlinkedTests,
    )
    try container.encode(
      notes,
      forKey: .notes,
    )
    try container.encode(
      [RecordResultEntry(run)],
      forKey: .results,
    )
  }
}
