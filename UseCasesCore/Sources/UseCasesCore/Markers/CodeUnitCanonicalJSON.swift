/// Deterministic JSON for hashing, with object keys sorted by UTF-16 code unit.
///
/// This is NOT ``CanonicalJSON``. The semantic row hash sorts keys with
/// JavaScript's `localeCompare`; the marker system's canonical JSON sorts them
/// with `<` on JavaScript strings, which compares UTF-16 code units. The two
/// disagree on case (`B` < `a` here), on punctuation (`-` < `_` here) and on
/// astral characters: U+1F600 is stored as D83D DE00 and so sorts BELOW U+FFFF,
/// where Swift's own `String` ordering puts it above. Array order is kept, there
/// is no insignificant whitespace, and scalars are spelled as `JSON.stringify`
/// spells them.
public enum CodeUnitCanonicalJSON {
  public static func encode(_ value: JSONValue) throws(CodeUnitCanonicalJSONError) -> String {
    switch value {
    case .null, .bool, .string:
      return JSONWriter.encode(value)
    case let .number(number):
      guard number.isFinite else {
        throw .nonFiniteNumber
      }
      return JSONWriter.encode(value)
    case let .array(values):
      var members: [String] = []
      for element in values {
        try members.append(encode(element))
      }
      return "[" + members.joined(separator: ",") + "]"
    case let .object(object):
      return try encodeObject(object)
    }
  }

  /// The canonical form, hashed.
  public static func sha256(_ value: JSONValue) throws(CodeUnitCanonicalJSONError) -> String {
    try MarkerDigest.sha256(encode(value))
  }

  private static func encodeObject(_ object: JSONObject) throws(CodeUnitCanonicalJSONError)
    -> String
  {
    let sorted = object.pairs.sorted { left, right in
      left.key.utf16.lexicographicallyPrecedes(right.key.utf16)
    }
    var members: [String] = []
    for pair in sorted {
      let key = JSONWriter.encode(.string(pair.key))
      try members.append("\(key):\(encode(pair.value))")
    }
    let body = members.joined(separator: ",")
    return "{" + body + "}"
  }
}

/// Why a value has no canonical form.
public enum CodeUnitCanonicalJSONError: Error, Equatable, Sendable {
  /// NaN or an infinity, which cannot round-trip through JSON.
  case nonFiniteNumber

  /// The message the TypeScript throws. It carries no wire code: it is a
  /// programming error, never a diagnostic.
  public var message: String {
    switch self {
    case .nonFiniteNumber:
      "canonical_json: non-finite numbers are not serializable"
    }
  }
}
