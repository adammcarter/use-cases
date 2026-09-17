import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The opt-in keyring: parsing, loading, and the fail-closed resolvers that
/// gate a key by status and validity window.
struct KeyringTests {
  @Test
  func `parsing accepts and refuses exactly what the TypeScript does`() throws {
    for entry in try MarkersLedgerFixtures.section("keyring_parse") {
      let value = try MarkersLedgerFixtures.parsed(entry, "text")
      let expected = try #require(entry["result"])
      let name = entry["name"]?.stringValue ?? ""

      do throws(KeyringError) {
        _ = try Keyring.parse(value, sourcePath: "keyring.json")
        #expect(expected["ok"] == .bool(true), "\(name)")
      } catch {
        #expect(expected["ok"] == .bool(false), "\(name)")
        #expect(expected["code"]?.stringValue == error.code, "\(name)")
        #expect(expected["message"]?.stringValue == error.message, "\(name)")
      }
    }
  }

  @Test
  func `loading an unreadable path reports the node error text`() throws {
    for entry in try MarkersLedgerFixtures.section("keyring_load") {
      let path = try MarkersLedgerFixtures.string(entry, "path")

      let error = #expect(throws: KeyringError.self) {
        try Keyring.load(filePath: path)
      }
      #expect(error?.code == entry["code"]?.stringValue)
      #expect(error?.message == entry["message"]?.stringValue)
    }
  }

  @Test
  func `loading a file that is not JSON is keyring_invalid_json`() throws {
    let directory = try TemporaryDirectory()
    let file = try directory.writeFile("keyring.json", contents: "{ nope")

    let error = #expect(throws: KeyringError.self) {
      try Keyring.load(filePath: file.path)
    }
    #expect(error?.code == "keyring_invalid_json")
    #expect(error?.message.hasPrefix("keyring file \(file.path) is not valid JSON: ") == true)
  }

  @Test
  func `loading a valid keyring file builds the same resolver as parsing it`() throws {
    let rich = try MarkersLedgerFixtures.entry("rich", in: "keyring_parse")
    let directory = try TemporaryDirectory()
    let file = try directory.writeFile(
      "keys/keyring.json",
      contents: MarkersLedgerFixtures.string(rich, "text"),
    )
    let primary = try MarkersLedgerFixtures.pem("primary", "public_pem")

    let resolver = try Keyring.publicKeyResolver(fromFile: file.path)

    #expect(resolver("ci-key-1", "2026-06-01T00:00:00Z") == primary)
    #expect(resolver("ci-key-1", nil) == nil)
  }

  @Test(arguments: MarkersLedgerGoldenCorpus.keyringResolverCaseNames)
  func `every resolver answers a query as the TypeScript does`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "keyring_resolver")
    let rich = try MarkersLedgerFixtures.entry("rich", in: "keyring_parse")
    let keyring = try Keyring.parse(MarkersLedgerFixtures.parsed(rich, "text"), sourcePath: nil)
    let keyIdentifier = try MarkersLedgerFixtures.string(entry, "key_id")
    let createdAt = entry["created_at"]?.stringValue

    #expect(keyring.publicKeyResolver()(keyIdentifier, createdAt) == entry["public_key"]?
      .stringValue)
    #expect(keyring.maxAssuranceTierResolver()(keyIdentifier, createdAt)?.rawValue
      == entry["max_assurance_tier"]?.stringValue)
    let credential = keyring.webAuthnCredentialResolver()(keyIdentifier, createdAt)
    #expect((credential?.jsonValue).map(MarkersLedgerFixtures.wire)
      == entry["webauthn_credential"]
      .flatMap { value in
        value == .null ? nil : MarkersLedgerFixtures.wire(value)
      })
  }

  @Test(arguments: MarkersLedgerGoldenCorpus.dateParseCaseNames)
  func `a validity timestamp parses to V8's milliseconds`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "date_parse")
    let input = try MarkersLedgerFixtures.string(entry, "input")

    #expect(JavaScriptDate.parse(input) == entry["milliseconds"]?.numberValue)
  }

  /// V8 hands these to its legacy date parser, which is not ported. They are
  /// pinned so the difference stays visible: V8 reads a time, Swift reads none,
  /// and a key gated on such a timestamp fails CLOSED here.
  @Test
  func `legacy date forms are the recorded, fail-closed difference`() throws {
    for entry in try MarkersLedgerFixtures.section("legacy_date_parse") {
      let input = try MarkersLedgerFixtures.string(entry, "input")

      #expect(entry["milliseconds"]?.numberValue != nil, "\(input)")
      #expect(JavaScriptDate.parse(input) == nil, "\(input)")
    }
  }

  @Test
  func `a date-time without an offset is local time, as in JavaScript`() throws {
    let local = try #require(JavaScriptDate.parse("2026-07-01T12:00:00"))
    let utc = try #require(JavaScriptDate.parse("2026-07-01T12:00:00Z"))
    let offset = TimeZone.current.secondsFromGMT(for: Date(timeIntervalSince1970: utc / 1000))

    #expect(utc - local == Double(offset) * 1000)
  }

  @Test
  func `an ed25519 key never lends hardware assurance`() {
    let validity = KeyringKeyValidity(
      validFrom: "2026-01-01T00:00:00Z",
      validUntil: nil,
      status: .active,
      maxAssuranceTier: .webAuthnHardware,
    )
    let keyring = Keyring(keys: [
      .ed25519(Ed25519KeyringKey(keyIdentifier: "k", publicKey: "pem", validity: validity)),
      .webAuthn(WebAuthnKeyringCredential(
        credentialIdentifier: "c",
        credentialPublicKeyAlgorithm: -257,
        credentialPublicKeySPKI: "spki",
        validity: validity,
      )),
    ])

    #expect(keyring.maxAssuranceTierResolver()("k", "2026-02-01T00:00:00Z") == .untrustedAutomation)
    #expect(keyring.webAuthnCredentialResolver()("c", "2026-02-01T00:00:00Z") == nil)
  }

  @Test
  func `unreadable keyrings report node's errno text`() throws {
    let directory = try TemporaryDirectory()
    let locked = try directory.writeFile("locked.json", contents: "{}")
    try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: locked.path)
    let underFile = locked.appendingPathComponent("keyring.json").path

    let denied = #expect(throws: KeyringError.self) {
      try Keyring.load(filePath: locked.path)
    }
    let notDirectory = #expect(throws: KeyringError.self) {
      try Keyring.load(filePath: underFile)
    }

    let deniedDetail = "EACCES: permission denied, open '\(locked.path)'"
    #expect(denied?.message == "could not read keyring file \(locked.path): \(deniedDetail)")
    #expect(notDirectory?.message
      == "could not read keyring file \(underFile): ENOTDIR: not a directory, open '\(underFile)'")
  }
}
