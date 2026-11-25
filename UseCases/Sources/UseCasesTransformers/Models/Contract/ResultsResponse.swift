import Foundation

/// What a results transformer writes to `response.json`.
struct ResultsResponse: Encodable, Equatable, Sendable {
  let contract = 1
  let results: [LinkResult]
  let unlinked: [UnlinkedTest]
  let diagnostics: [String]

  init(
    results: [LinkResult] = [],
    unlinked: [UnlinkedTest] = [],
    diagnostics: [String] = [],
  ) {
    self.results = results
    self.unlinked = unlinked
    self.diagnostics = diagnostics
  }
}
