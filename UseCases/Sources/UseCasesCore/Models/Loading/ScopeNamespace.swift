/// A scope of a loaded workspace, and the namespace its use cases are composed under: the
/// prefixes the scope and the scopes above it declare, the root's first (chapter 04).
struct ScopeNamespace: Equatable, Sendable {
  let scope: LoadedScope
  let segments: [IdentifierSegment]

  /// The namespace as an id spells it; empty when no scope declares a prefix.
  var text: String {
    segments.map(\.text).joined(separator: ".")
  }
}
