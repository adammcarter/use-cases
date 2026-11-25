/// The `--json` document of `use-cases links` (`cli-links.schema.json`). Every link has the shape
/// a transformer receives (chapter 10): lines, never bytes.
struct LinksDocument: Encodable {
  let links: [LinkEntry]
  let diagnostics: [String]

  enum CodingKeys: String, CodingKey {
    case outputVersion = "output_version"
    case command
    case links
    case diagnostics
  }

  func encode(to encoder: any Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(
      OutputDocument.version,
      forKey: .outputVersion,
    )
    try container.encode(
      LinksCommand.name,
      forKey: .command,
    )
    try container.encode(
      links,
      forKey: .links,
    )
    try container.encode(
      diagnostics,
      forKey: .diagnostics,
    )
  }
}
