/// The resource files of one route, ready to fingerprint, and what stopped the rest.
struct ResourceContributions: Equatable, Sendable {
  var contributions: [ResourceContribution] = []
  var diagnostics: [Diagnostic] = []
}
