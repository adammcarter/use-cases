/// The canonical JSON form a semantic hash is taken over.
///
/// Object members are sorted the way JavaScript's `localeCompare` sorts them —
/// punctuation before letters, lowercase before uppercase — because that is what
/// the TypeScript does, and a different order is a different hash.
enum CanonicalJSON {
  static func encode(_ value: JSONValue) -> String {
    JSONWriter.encode(value, sortingKeys: true)
  }
}
