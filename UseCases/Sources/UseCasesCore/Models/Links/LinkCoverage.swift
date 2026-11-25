/// Which use cases and routes have links at all (chapter 08 "Cardinality"): what the missing-link
/// warnings of `status` are built from.
struct LinkCoverage: Sendable {
  private let implemented: Set<String>
  private let validated: Set<Key>

  init(_ links: [ResolvedLink]) {
    var implemented: Set<String> = []
    var validated: Set<Key> = []

    for link in links {
      guard let route = link.route else {
        implemented.insert(link.useCase)
        continue
      }

      validated.insert(
        Key(
          useCase: link.useCase,
          route: route,
        ),
      )
    }

    self.implemented = implemented
    self.validated = validated
  }

  /// Whether the use case has at least one implementation link.
  func hasImplementationLink(useCase: String) -> Bool {
    implemented.contains(useCase)
  }

  /// Whether the route has at least one validation link.
  func hasValidationLink(
    useCase: String,
    route: String,
  ) -> Bool {
    validated.contains(
      Key(
        useCase: useCase,
        route: route,
      ),
    )
  }

  private struct Key: Hashable, Sendable {
    let useCase: String
    let route: String
  }
}
