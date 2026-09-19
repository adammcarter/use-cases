/// The canonical identifier grammar, mirroring
/// `schemas/v1/common.schema.json` `$defs.id`.
///
/// This is the single guard that keeps a user-supplied id (a showcase run id, a
/// plan item id, an evidence id) from becoming a path-traversal segment: it
/// forbids `/`, `\`, `..`, leading separators and absolute paths, so an
/// identifier that passes is always one safe path segment.
public enum CanonicalIdentifier {
  /// `ident ("." ident)*` where `ident` is `[a-z0-9][a-z0-9_-]*`.
  private static var grammar: Regex<Substring> {
    /[a-z0-9][a-z0-9_\-]*(?:\.[a-z0-9][a-z0-9_\-]*)*/
  }

  /// True when `value` matches the canonical identifier grammar.
  public static func isValid(_ value: String) -> Bool {
    value.wholeMatch(of: grammar) != nil
  }

  /// Throw ``PathError/invalidIdentifier(parameterName:value:)`` unless `value`
  /// is a canonical identifier. Call this at every boundary where a supplied id
  /// becomes a path segment, BEFORE the id is joined into a path.
  public static func assertValid(
    _ value: String,
    parameterName: String,
  ) throws(PathError) {
    guard isValid(value) else {
      throw .invalidIdentifier(parameterName: parameterName, value: value)
    }
  }
}
