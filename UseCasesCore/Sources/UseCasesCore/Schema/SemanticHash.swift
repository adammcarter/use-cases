import Crypto
import Foundation

/// The content hash of a document, stable across key order.
public enum SemanticHash {
  /// `sha256:<hex>` over the canonical JSON form of `value`.
  public static func compute(_ value: JSONValue) -> String {
    let digest = SHA256.hash(data: Data(CanonicalJSON.encode(value).utf8))
    let hexadecimal = digest
      .map { byte in
        String(format: "%02x", byte)
      }
      .joined()
    return "sha256:\(hexadecimal)"
  }
}
