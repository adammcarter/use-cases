import Crypto
import Foundation

/// `sha256:<hex>` digests, as the marker TypeScript spells them.
///
/// Not ``SemanticHash``: that canonicalizes a document first. These hash the
/// exact UTF-8 bytes they are given.
public enum MarkerDigest {
  /// sha256 over the UTF-8 bytes of `text`.
  public static func sha256(_ text: String) -> String {
    sha256(bytes: Array(text.utf8))
  }

  /// sha256 over raw bytes.
  public static func sha256(bytes: [UInt8]) -> String {
    let hexadecimal = SHA256.hash(data: Data(bytes))
      .map { byte in
        String(format: "%02x", byte)
      }
      .joined()
    return "sha256:\(hexadecimal)"
  }
}
