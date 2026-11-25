/// A value a fingerprint payload may hold (chapter 11 §89.1): null, a boolean, an integer, a
/// string, an array or an object.
///
/// An object keeps its members in a list, not a dictionary: a dictionary would treat a key in two
/// Unicode forms as one key and lose the order members were given in. The encoder sorts them.
enum CanonicalValue: Sendable {
  case null
  case boolean(Bool)
  case integer(Int)
  case string(String)
  case array([CanonicalValue])
  case object([CanonicalMember])

  /// An object from members written out, in any order.
  static func members(_ pairs: KeyValuePairs<String, CanonicalValue>) -> CanonicalValue {
    .object(
      pairs.map { pair in
        CanonicalMember(
          key: pair.key,
          value: pair.value,
        )
      },
    )
  }

  /// An array of strings, in the order given.
  static func strings(_ texts: [String]) -> CanonicalValue {
    .array(
      texts.map { text in
        .string(text)
      },
    )
  }
}
