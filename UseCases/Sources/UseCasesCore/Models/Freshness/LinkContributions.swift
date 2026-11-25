/// The bindings of one collection of links, ready to fingerprint, and what stopped the rest.
struct LinkContributions: Equatable, Sendable {
  var contributions: [LinkContribution]
  var diagnostics: [Diagnostic]
}
