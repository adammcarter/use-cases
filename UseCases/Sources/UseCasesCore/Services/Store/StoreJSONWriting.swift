/// Prints the JSON the store's files are made of, by hand, so the bytes are the same on every
/// machine and a test can name them.
public protocol StoreJSONWriting: Sendable {
  /// UTF-8, members sorted by the bytes of their keys, no white space at all.
  func compact(_ value: StoreJSONValue) -> [UInt8]

  /// UTF-8, members sorted by the bytes of their keys, two spaces of indent, `": "` after a key,
  /// an empty array or object as `[]` or `{}`, and a line feed at the end.
  func pretty(_ value: StoreJSONValue) -> [UInt8]
}
