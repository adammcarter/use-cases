/// What the core writes to `request.json` for a results job. Fields this version does not know are
/// ignored (ADR 015).
struct ResultsRequest: Decodable, Equatable, Sendable {
  let links: [RequestLink]
  let output: ReportOutput
  let codeRoot: String
  let settings: TransformerSettings

  init(
    links: [RequestLink],
    output: ReportOutput,
    codeRoot: String,
    settings: TransformerSettings = .empty,
  ) {
    self.links = links
    self.output = output
    self.codeRoot = codeRoot
    self.settings = settings
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    links = try container.decode(
      [RequestLink].self,
      forKey: .links,
    )
    output = try container.decode(
      ReportOutput.self,
      forKey: .output,
    )
    codeRoot = try container.decode(
      String.self,
      forKey: .codeRoot,
    )
    settings = try container.decodeIfPresent(
      TransformerSettings.self,
      forKey: .settings,
    ) ?? .empty
  }

  private enum CodingKeys: String, CodingKey {
    case links
    case output
    case codeRoot = "code_root"
    case settings
  }
}
