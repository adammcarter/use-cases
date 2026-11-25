/// A JSON value one of the store's files is printed from (chapter 12): `run.json`, a line of
/// `results.jsonl`, `completion.json` and `run-order.json`, and a transformer's request
/// (chapter 10 §10).
///
/// An object keeps its members in a list, as ``CanonicalValue`` does, and ``StoreJSONWriter``
/// sorts them, so a file reads the same every time it is written.
public enum StoreJSONValue: Equatable, Sendable {
  /// JSON `null`.
  case null

  /// `true` or `false`.
  case boolean(Bool)

  /// A whole number, written without a fraction or an exponent.
  case integer(Int)

  /// Any other number.
  case number(Double)

  /// Text.
  case string(String)

  /// Values in order.
  case array([StoreJSONValue])

  /// Members, each key once.
  case object([StoreJSONMember])

  /// An object from members written out, in any order.
  public static func members(_ pairs: KeyValuePairs<String, StoreJSONValue>) -> StoreJSONValue {
    .object(
      pairs.map { pair in
        StoreJSONMember(
          key: pair.key,
          value: pair.value,
        )
      },
    )
  }

  /// An array of strings, in the order given.
  public static func strings(_ texts: [String]) -> StoreJSONValue {
    .array(
      texts.map { text in
        .string(text)
      },
    )
  }

  /// An object whose members are the given members, left out when they are `nil`. This is how
  /// an optional field of a document is written: absent, never `null`.
  public static func present(_ pairs: KeyValuePairs<String, StoreJSONValue?>) -> StoreJSONValue {
    .object(
      pairs.compactMap { pair in
        pair.value.map { value in
          StoreJSONMember(
            key: pair.key,
            value: value,
          )
        }
      },
    )
  }
}
