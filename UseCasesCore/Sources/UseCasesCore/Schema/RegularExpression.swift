/// The `pattern` keyword. Patterns are written in ECMAScript syntax and are
/// tested the way `RegExp.prototype.test` tests them: an unanchored pattern may
/// match anywhere, and `$` means the END of the string.
///
/// Swift's own engine is used rather than `NSRegularExpression` for exactly that
/// last reason — ICU lets `$` match before a trailing newline, so an id ending in
/// one would be accepted here and refused in TypeScript.
enum RegularExpression {
  /// Every pattern this binary can ever be asked to match against known
  /// ahead of time — the embedded, frozen schemas' `"pattern"` values, and
  /// `YamlParser`'s own fixed patterns — compiled once. `nonisolated(unsafe)`
  /// on a `static let` is the narrow, sanctioned tool for it: `Regex` carries
  /// no `Sendable` conformance in this toolchain even though a built value is
  /// immutable, and this one is built exactly once — Swift's static
  /// initializer runs a `let` initializer exactly once even under concurrent
  /// first access — and never written again, so every read afterwards is of
  /// already-immutable data. That is a narrower claim than marking the TYPE
  /// itself safe without proof, which is what the house rule against that
  /// pattern exists to stop: nothing about `Regex` itself is asserted safe
  /// here, only this one write-once global's access pattern.
  ///
  /// Recompiling per call was measured costing `scan` roughly twenty seconds
  /// on an 803-row matrix, and caching only the schema-derived patterns did
  /// not touch that cost: the actual majority of the work is `YamlParser`
  /// checking every plain scalar in every row against its own ten fixed
  /// patterns before it resolves to a plain string, and none of those
  /// literals appear inside a schema's `"pattern"` keyword, so they were
  /// never in this cache until `YamlParser.allPatterns` was added below.
  private nonisolated(unsafe) static let knownPatterns: [String: Regex<AnyRegexOutput>] = {
    var compiled: [String: Regex<AnyRegexOutput>] = [:]
    for pattern in patternsInEmbeddedSchemas().union(YamlParser.allPatterns) {
      compiled[pattern] = compile(pattern)
    }
    return compiled
  }()

  static func matches(
    _ text: String,
    _ pattern: String,
  ) -> Bool {
    guard let expression = knownPatterns[pattern] ?? compile(pattern) else {
      return false
    }
    return text.firstMatch(of: expression) != nil
  }

  private static func compile(_ pattern: String) -> Regex<AnyRegexOutput>? {
    try? Regex(pattern).matchingSemantics(.unicodeScalar)
  }

  /// Every `"pattern"` value anywhere in the embedded schemas, found by
  /// walking the parsed document rather than hand-listing them, so a schema
  /// regenerated with a new pattern is covered without touching this file.
  private static func patternsInEmbeddedSchemas() -> Set<String> {
    var found: Set<String> = []
    for source in EmbeddedSchemas.byFileName.values {
      guard let document = try? JSONParser.parse(source) else {
        continue
      }
      collectPatterns(from: document, into: &found)
    }
    return found
  }

  private static func collectPatterns(
    from value: JSONValue,
    into found: inout Set<String>,
  ) {
    switch value {
    case let .object(object):
      for (key, member) in object.pairs {
        if key == "pattern", let pattern = member.stringValue {
          found.insert(pattern)
        }
        collectPatterns(from: member, into: &found)
      }

    case let .array(items):
      for item in items {
        collectPatterns(from: item, into: &found)
      }

    case .null, .bool, .number, .string:
      break
    }
  }
}
