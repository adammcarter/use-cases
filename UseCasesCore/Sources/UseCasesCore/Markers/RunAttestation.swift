import Crypto
import Foundation

/// Run attestation for the UNSIGNED verification-results ledger
/// (runAttestation.ts).
///
/// Every record `verify` writes carries an HMAC-SHA256 over its own canonical
/// JSON, keyed by 32 random bytes minted on this machine and kept outside the
/// repository, so a hand-typed line has no valid attestation. It is
/// tamper-EVIDENT, not tamper-proof: anyone who can read the key can forge one.
public enum RunAttestation {
  /// The record field carrying the attestation.
  public static let field = "run_attestation"

  private static let algorithm = "hmac-sha256"
  private static let keyByteCount = 32

  /// `hmac-sha256:<hex>` over the record's canonical JSON, the record's own
  /// attestation excluded. The key is read as node reads hex: leniently.
  public static func compute(
    record: JSONObject,
    key: String,
  ) throws(CodeUnitCanonicalJSONError) -> String {
    var payload = record
    payload[field] = nil
    let canonical = try CodeUnitCanonicalJSON.encode(.object(payload))
    let code = HMAC<SHA256>.authenticationCode(
      for: Data(canonical.utf8),
      using: SymmetricKey(data: NodeBuffer.hexDecode(key)),
    )
    return "\(algorithm):\(NodeBuffer.hexadecimal(code))"
  }

  /// True only for a record carrying the attestation this key produces. False,
  /// failing closed, when there is no well-formed key at all.
  public static func verify(
    record: JSONObject,
    key: String?,
  ) throws(CodeUnitCanonicalJSONError) -> Bool {
    guard let key, isRunKey(key),
          let claimed = record[field]?.stringValue, !claimed.isEmpty
    else {
      return false
    }
    let expected = try Array(compute(record: record, key: key).utf16)
    let claimedUnits = Array(claimed.utf16)
    guard claimedUnits.count == expected.count else {
      return false
    }
    var difference: UInt16 = 0
    for (left, right) in zip(claimedUnits, expected) {
      difference |= left ^ right
    }
    return difference == 0
  }

  /// The machine-local key, minted on first use. A missing, empty or malformed
  /// key file is REPLACED, never raised: a corrupt key degrades to "previous
  /// results read unattested", not to a crashed verify.
  public static func resolveLocalRunKey(
    keyPath: String,
    files: some TextFileStoring,
    mintKey: () -> String = mintRunKey,
  ) throws(FileAccessError) -> String {
    if let existing = try readLocalRunKey(keyPath: keyPath, files: files) {
      return existing
    }
    let minted = mintKey()
    try files.writeText("\(minted)\n", toPath: keyPath)
    return minted
  }

  /// The machine-local key, or nil when there is none. Never mints one: `scan`
  /// is strictly read-only.
  public static func readLocalRunKey(
    keyPath: String,
    files: some TextFileStoring,
  ) throws(FileAccessError) -> String? {
    guard let text = try files.readText(atPath: keyPath) else {
      return nil
    }
    let existing = JavaScriptString.trim(text)
    return isRunKey(existing) ? existing : nil
  }

  /// `UC_RUN_KEY_FILE` when it is set to something other than whitespace,
  /// trimmed; otherwise `<home>/.use-cases/run-key`, joined as `path.join`
  /// joins it.
  public static func defaultRunKeyPath(
    environment: [String: String],
    homeDirectory: String,
  ) -> String {
    if let override = environment["UC_RUN_KEY_FILE"] {
      let trimmed = JavaScriptString.trim(override)
      if !trimmed.isEmpty {
        return trimmed
      }
    }
    let joined = [homeDirectory, ".use-cases", "run-key"]
      .filter { !$0.isEmpty }
      .joined(separator: "/")
    return WorkspacePath.normalize(joined)
  }

  /// 32 random bytes, as lowercase hex.
  public static func mintRunKey() -> String {
    var generator = SystemRandomNumberGenerator()
    let bytes = (0 ..< keyByteCount).map { _ in
      UInt8.random(in: .min ... .max, using: &generator)
    }
    return NodeBuffer.hexadecimal(bytes)
  }

  /// `/^[0-9a-f]{64}$/`.
  static func isRunKey(_ key: String) -> Bool {
    let units = Array(key.utf16)
    return units.count == 64 && units.allSatisfy { unit in
      CodeUnits.isASCIIDigit(unit) || (0x61 ... 0x66).contains(unit)
    }
  }
}
