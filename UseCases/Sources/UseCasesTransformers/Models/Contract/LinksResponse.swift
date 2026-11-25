/// What a links transformer writes to `response.json`.
struct LinksResponse: Encodable, Equatable, Sendable {
  let contract = 1
  let links: [ProducedLink]
  let diagnostics: [String]

  init(
    links: [ProducedLink] = [],
    diagnostics: [String] = [],
  ) {
    self.links = links
    self.diagnostics = diagnostics
  }
}
