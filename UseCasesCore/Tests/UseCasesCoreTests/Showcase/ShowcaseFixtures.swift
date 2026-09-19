import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Access to the generated TypeScript showcase corpus, and the Swift calls each
/// recorded step names, so a step's result can be compared with what the
/// TypeScript returned as wire bytes.
enum ShowcaseFixtures {
  static let golden: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(ShowcaseGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  static func section(_ name: String) throws -> JSONValue {
    try #require(golden.get()[name], "corpus has no section \(name)")
  }

  static func goldenCase(
    _ name: String,
    in sectionName: String,
  ) throws -> JSONValue {
    let cases = try #require(
      section(sectionName).arrayValue,
      "section \(sectionName) is not a list",
    )
    return try #require(cases.first { $0["name"]?.stringValue == name }, "no case \(name)")
  }

  static func wire(_ value: JSONValue?) -> String {
    UseCasesFixtures.wire(value)
  }

  /// Two wire forms compared, a failure naming `label` and showing only the
  /// neighbourhood of the first differing code unit — a run's results carry
  /// whole plans, and the full text would bury the difference.
  static func expectSameWire(
    _ actual: String,
    _ expected: String,
    _ label: String,
    sourceLocation: SourceLocation = #_sourceLocation,
  ) {
    guard actual != expected else {
      return
    }
    let actualUnits = Array(actual.utf16)
    let expectedUnits = Array(expected.utf16)
    let offset = zip(actualUnits, expectedUnits).prefix { pair in
      pair.0 == pair.1
    }.count
    func window(_ units: [UInt16]) -> String {
      let start = max(0, offset - 80)
      let end = min(units.count, offset + 80)
      return String(decoding: units[start ..< end], as: UTF16.self)
    }
    let actualWindow = window(actualUnits)
    let expectedWindow = window(expectedUnits)
    let message = "\(label) differs at \(offset):\n  actual   …\(actualWindow)…"
      + "\n  expected …\(expectedWindow)…"
    Issue.record(Comment(rawValue: message), sourceLocation: sourceLocation)
  }

  /// The fixture workspace every run case starts from, built for real.
  static func workspace() throws -> UseCasesFixtures.Workspace {
    let files = try #require(section("base_tree").arrayValue)
    let tree = files.map { file in
      JSONValue.object(JSONObject([
        ("kind", .string("file")),
        ("path", file["path"] ?? .null),
        ("text", file["text"] ?? .null),
      ]))
    }
    return try UseCasesFixtures.Workspace(tree: .array(tree))
  }

  static func privateKeyPEM(_ name: String) throws -> String {
    try #require(section("keys")[name]?["private_pem"]?.stringValue, "no key \(name)")
  }

  static func keyring(_ name: String) throws -> Keyring {
    let value = try #require(section("keyrings")[name], "no keyring \(name)")
    return try Keyring.parse(value, sourcePath: "\(name).json")
  }

  /// The generator's `resolversFor`: a public-key resolver unless
  /// `resolver: false`, and the tier and credential resolvers when asked for.
  static func resolvers(_ arguments: JSONValue) throws -> ShowcaseTrustResolvers {
    guard let name = arguments["keyring"]?.stringValue else {
      return .none
    }
    let keyring = try keyring(name)
    return ShowcaseTrustResolvers(
      publicKeyResolver: arguments["resolver"] == .bool(false) ? nil : keyring.publicKeyResolver(),
      tierResolver: arguments["tier_resolver"] == .bool(true) ? keyring
        .maxAssuranceTierResolver() : nil,
      webAuthnCredentialResolver: arguments["webauthn_resolver"] == .bool(true)
        ? keyring.webAuthnCredentialResolver() : nil,
    )
  }

  /// An inline credential map, resolved by id alone as the generator's
  /// `(id) => credentials[id]` resolves it. A cap the keyring enum cannot
  /// spell (`bogus`) is read as the weakest tier, which is what the
  /// TypeScript's `normalizeAssuranceTier` makes of it.
  static func credentialResolver(_ credentials: JSONValue)
    -> @Sendable (String, String?) -> WebAuthnCredential?
  {
    var byIdentifier: [String: WebAuthnCredential] = [:]
    for member in credentials.objectValue?.pairs ?? [] {
      let credential = member.value
      byIdentifier[member.key] = WebAuthnCredential(
        credentialIdentifier: credential["credential_id"]?.stringValue ?? "",
        credentialPublicKeyAlgorithm: Int(credential["credential_public_key_alg"]?
          .numberValue ?? 0),
        credentialPublicKeySPKI: credential["credential_public_key_spki"]?.stringValue ?? "",
        maxAssuranceTier: KeyringAssuranceTier(
          rawValue: credential["max_assurance_tier"]?.stringValue ?? "",
        ) ?? .untrustedAutomation,
      )
    }
    let resolved = byIdentifier
    return { identifier, _ in resolved[identifier] }
  }

  /// A thrown error as the generator recorded it. A plan file's JSON parse
  /// error keeps its prefix; `JSON.parse`'s own wording is accepted as
  /// differing (docs/rewrite/ladder-notes.md, row 4).
  static func expectThrown(
    _ error: ShowcaseError,
    equals expected: JSONValue,
    in workspace: UseCasesFixtures.Workspace?,
    sourceLocation: SourceLocation = #_sourceLocation,
  ) {
    let expectedMessage = expected["message"]?.stringValue ?? ""
    let detokenized = workspace?.detokenized(expectedMessage) ?? expectedMessage
    if let code = expected["code"]?.stringValue {
      #expect(error.code == code, sourceLocation: sourceLocation)
    }
    if detokenized.contains(" in JSON at position ") {
      #expect(
        error.message.hasPrefix("Presentation plan file could not be read: "),
        sourceLocation: sourceLocation,
      )
    } else {
      #expect(error.message == detokenized, sourceLocation: sourceLocation)
    }
  }

  // MARK: - Injected externalities

  struct FixedClock: ShowcaseClock {
    let milliseconds: Double

    func now() -> Double {
      milliseconds
    }
  }

  struct FixedUUIDSource: ShowcaseUUIDSource {
    let uuid: String

    func randomUUID() -> String {
      uuid
    }
  }
}
