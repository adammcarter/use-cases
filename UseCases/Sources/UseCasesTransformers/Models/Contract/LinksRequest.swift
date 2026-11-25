/// What the core writes to `request.json` for a links job. Fields this version does not know are
/// ignored (ADR 015).
struct LinksRequest: Decodable, Equatable, Sendable {
  let useCases: [UseCaseReference]
  let codeRoot: String
  let settings: TransformerSettings

  init(
    useCases: [UseCaseReference],
    codeRoot: String,
    settings: TransformerSettings = .empty,
  ) {
    self.useCases = useCases
    self.codeRoot = codeRoot
    self.settings = settings
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)

    useCases = try container.decode(
      [UseCaseReference].self,
      forKey: .useCases,
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
    case useCases = "use_cases"
    case codeRoot = "code_root"
    case settings
  }
}
