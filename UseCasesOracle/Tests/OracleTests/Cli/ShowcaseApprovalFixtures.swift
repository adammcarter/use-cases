import CryptoKit
import Foundation
import Testing

/// The trusted human sign-off path, and the forgeries it has to refuse.
///
/// The TypeScript oracle mints its ed25519 pair with `node:crypto`. The Swift
/// oracle links nothing, so the pair comes from CryptoKit — a system framework,
/// not a package dependency — and is wrapped in the two fixed DER envelopes
/// ed25519 uses, which is all a PKCS#8/SPKI PEM for this curve is. The key is
/// still INDEPENDENT of the binary under test, which is the property that
/// matters: an oracle that asked the product to mint the key it then verifies
/// would prove nothing.
enum ShowcaseApproval {
  struct KeyPair {
    let publicKeyPem: String
    let privateKeyPem: String
  }

  /// PKCS#8 and SPKI prefixes for ed25519: both are fixed byte strings with the
  /// raw 32-byte key appended (RFC 8410).
  private static let pkcs8Prefix = Data([
    0x30, 0x2E, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06,
    0x03, 0x2B, 0x65, 0x70, 0x04, 0x22, 0x04, 0x20,
  ])

  private static let spkiPrefix = Data([
    0x30, 0x2A, 0x30, 0x05, 0x06, 0x03, 0x2B, 0x65, 0x70, 0x03, 0x21, 0x00,
  ])

  static func ed25519Pem() -> KeyPair {
    let key = Curve25519.Signing.PrivateKey()
    return KeyPair(
      publicKeyPem: pem("PUBLIC KEY", spkiPrefix + key.publicKey.rawRepresentation),
      privateKeyPem: pem("PRIVATE KEY", pkcs8Prefix + key.rawRepresentation),
    )
  }

  private static func pem(
    _ label: String,
    _ der: Data,
  ) -> String {
    let encoded = Array(der.base64EncodedString())
    let lines = stride(from: 0, to: encoded.count, by: 64).map { offset in
      String(encoded[offset ..< min(offset + 64, encoded.count)])
    }
    return "-----BEGIN \(label)-----\n\(lines.joined(separator: "\n"))\n-----END \(label)-----\n"
  }

  static func writeKeyring(
    _ directory: TemporaryDirectory,
    keyIdentifier: String,
    publicKeyPem: String,
  ) throws -> String {
    let keyring = OracleJson.object([
      "keyring_schema_id": .string("ucase-public-key-registry-v1"),
      "keys": .array([
        .object([
          "key_id": .string(keyIdentifier),
          "algorithm": .string("ed25519"),
          "public_key": .string(publicKeyPem),
          "valid_from": .string("2026-01-01T00:00:00Z"),
          "valid_until": .null,
          "status": .string("active"),
          "max_assurance_tier": .string("trusted_host_user_presence"),
        ]),
      ]),
    ])
    try directory.writeFile("keyring.json", contents: keyring.encoded)
    return directory.url.appendingPathComponent("keyring.json").path
  }

  /// The trusted human sign-off path in full: `request-approval` mints an
  /// UNSIGNED request (the MCP/agent half); `approve-run` — run in the human's
  /// OWN shell against a key the agent never sees — is the only thing that can
  /// turn it into a signed token.
  static func signTrustedApproval(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
    key: KeyPair,
    keyIdentifier: String,
  ) async throws -> (tokenPath: String, keyringPath: String) {
    let requested = try await ShowcaseWorkspace.run(
      directory,
      ["showcase", "request-approval", "--repo", ".", "--run", runIdentifier],
    )
    try directory.writeFile("approval-request.json", contents: requested.standardOutput)
    try directory.writeFile("human.key.pem", contents: key.privateKeyPem)
    let tokenPath = directory.url.appendingPathComponent("approval-token.json").path

    let signed = try await ShowcaseWorkspace.run(directory, [
      "approve-run",
      "--request", directory.url.appendingPathComponent("approval-request.json").path,
      "--key-file", directory.url.appendingPathComponent("human.key.pem").path,
      "--key-id", keyIdentifier,
      "--decision", "approved",
      "--assurance-method", "os_presence",
      "--out", tokenPath,
    ])
    #expect(
      signed.isOk == true,
      Comment(rawValue: "approve-run failed: \(signed.standardError)\(signed.standardOutput)"),
    )

    let keyringPath = try writeKeyring(
      directory,
      keyIdentifier: keyIdentifier,
      publicKeyPem: key.publicKeyPem,
    )
    return (tokenPath, keyringPath)
  }

  /// Append a well-formed event straight to the ledger file, bypassing every
  /// CLI verb — standing in for anything that is not `use-cases showcase
  /// approve --approval-token` (a hand-edited ledger, a rogue script, an MCP
  /// write that skipped the verify+append core). Returns the forged event's id.
  @discardableResult
  static func appendRawEvent(
    _ directory: TemporaryDirectory,
    run runIdentifier: String,
    eventType: String,
    actorType: String,
    payload: OracleJson,
  ) throws -> String {
    let sequence = try ShowcaseWorkspace.readEvents(directory, run: runIdentifier).count + 1
    let eventIdentifier = "evt.forged.\(sequence)"
    let zeroes = String(repeating: "0", count: 64)
    let event = OracleJson.object([
      "schema_version": .number(1),
      "event_type": .string(eventType),
      "event_id": .string(eventIdentifier),
      "run_id": .string(runIdentifier),
      "aggregate_id": .string(runIdentifier),
      "sequence": .number(Double(sequence)),
      "recorded_at": .string("2026-06-25T13:00:00.000Z"),
      "actor_type": .string(actorType),
      "host_surface": .string("codex.cli"),
      "idempotency_key": .string("forged-\(sequence)"),
      "intent_digest": .string("sha256:\(zeroes)"),
      "payload": payload,
    ])
    try directory.appendFile(
      ShowcaseWorkspace.eventsPath(runIdentifier),
      contents: event.encoded + "\n",
    )
    return eventIdentifier
  }

  /// The payload shape a forged approval or rejection carries.
  static func forgedApprovalPayload(
    decision: String,
    statement: String,
    finishEventIdentifier: String,
  ) -> OracleJson {
    .object([
      "decision": .string(decision),
      "approver": .object([
        "type": .string("user"),
        "actor_type": .string("user"),
        "assurance_tier": .string("trusted_host_user_presence"),
      ]),
      "capture_method": .string("self_reported"),
      "approval_statement": .string(statement),
      "scope": .object([
        "plan_content_hash": .string("sha256:fake"),
        "finish_event_id": .string(finishEventIdentifier),
        "run_outcome": .string("passed"),
        "known_gap_count": .number(0),
      ]),
    ])
  }
}
