/// A full use-case id: the resolved namespace that explicit YAML composition produces
/// (chapters 04 and 05). It never comes from a file's path or name.
struct UseCaseIdentifier: Hashable, Sendable, CustomStringConvertible {
  let namespace: Namespace

  /// Reads a full id written out, such as one found in a marker.
  init(validating text: String) throws(IdentityError) {
    namespace = try Namespace(validating: text)
  }

  /// Composes scope prefixes, the file's prefix and the local id, in that order.
  ///
  /// `scopePrefixes` holds only the prefixes scopes declared, root first: a scope without one
  /// passes its parent's namespace through, so it adds nothing. With no prefix at all the id is
  /// the local id alone.
  init(
    scopePrefixes: [Namespace],
    filePrefix: Namespace?,
    localIdentifier: IdentifierSegment,
  ) {
    var composed = Namespace(localIdentifier)
    let prefixes = scopePrefixes + (filePrefix.map { [$0] } ?? [])

    for prefix in prefixes.reversed() {
      composed = prefix.appending(composed)
    }

    namespace = composed
  }

  var text: String {
    namespace.text
  }

  var description: String {
    text
  }
}
