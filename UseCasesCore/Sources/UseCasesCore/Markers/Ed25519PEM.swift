import Crypto
import Foundation

/// ed25519 keys in the PEM forms node reads and writes: an SPKI `PUBLIC KEY`
/// and a PKCS#8 `PRIVATE KEY`. swift-crypto only takes the raw 32 bytes, so the
/// fixed DER envelope around them is unwrapped and written here.
enum Ed25519PEM {
  /// `SEQUENCE { SEQUENCE { OID 1.3.101.112 } BIT STRING }`, then 32 bytes.
  static let publicKeyPrefix: [UInt8] = [
    0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00,
  ]

  /// `SEQUENCE { INTEGER 0, SEQUENCE { OID 1.3.101.112 }, OCTET STRING { OCTET
  /// STRING } }`, then the 32-byte seed.
  static let privateKeyPrefix: [UInt8] = [
    0x30, 0x2E, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
  ]

  /// The public key a PEM names. Like node's `createPublicKey`, a private key
  /// PEM yields its public half.
  static func publicKey(fromPEM pem: String) -> Curve25519.Signing.PublicKey? {
    guard let block = block(in: pem) else {
      return nil
    }
    switch block.label {
    case "PUBLIC KEY":
      guard let raw = unwrap(block.der, prefix: publicKeyPrefix) else {
        return nil
      }
      return try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
    case "PRIVATE KEY":
      return privateKey(der: block.der)?.publicKey
    default:
      return nil
    }
  }

  static func privateKey(fromPEM pem: String) -> Curve25519.Signing.PrivateKey? {
    guard let block = block(in: pem), block.label == "PRIVATE KEY" else {
      return nil
    }
    return privateKey(der: block.der)
  }

  static func pem(
    label: String,
    der: [UInt8],
  ) -> String {
    let body = Data(der).base64EncodedString(options: [
      .lineLength64Characters,
      .endLineWithLineFeed,
    ])
    return "-----BEGIN \(label)-----\n\(body)\n-----END \(label)-----\n"
  }

  private static func privateKey(der: [UInt8]) -> Curve25519.Signing.PrivateKey? {
    guard let seed = unwrap(der, prefix: privateKeyPrefix) else {
      return nil
    }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: seed)
  }

  private static func unwrap(
    _ der: [UInt8],
    prefix: [UInt8],
  ) -> [UInt8]? {
    guard der.count == prefix.count + 32, der.starts(with: prefix) else {
      return nil
    }
    return Array(der.dropFirst(prefix.count))
  }

  /// The first `-----BEGIN X-----` … `-----END X-----` block, read the way
  /// OpenSSL reads one: text before it is ignored, each line's trailing
  /// whitespace is dropped, and whitespace inside the base64 body is skipped.
  private static func block(in pem: String) -> (label: String, der: [UInt8])? {
    let lines = pem.components(separatedBy: "\n").map { line in
      String(line.reversed().drop { $0 == " " || $0 == "\t" || $0 == "\r" }.reversed())
    }
    guard let begin = lines.firstIndex(where: isBeginLine) else {
      return nil
    }
    let label = String(lines[begin].dropFirst("-----BEGIN ".count).dropLast("-----".count))
    let endLine = "-----END \(label)-----"
    guard let end = lines[(begin + 1)...].firstIndex(of: endLine) else {
      return nil
    }
    let body = lines[(begin + 1) ..< end]
      .joined()
      .filter { $0 != " " && $0 != "\t" }
    guard let der = Data(base64Encoded: body) else {
      return nil
    }
    return (label, [UInt8](der))
  }

  private static func isBeginLine(_ line: String) -> Bool {
    line.hasPrefix("-----BEGIN ") && line.hasSuffix("-----") && line.count > "-----BEGIN -----"
      .count
  }
}
