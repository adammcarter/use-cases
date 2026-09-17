import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// The three optional config sections — verifiers, the release gate and the
/// approval trust anchor — normalized out of a real `use-cases.yml`.
///
/// The keyring and its keys are carried RAW here: `markers/keyring.ts` has not
/// been ported yet, so the shape survives round-tripping untouched and a later
/// row gives it a type.
struct WorkspaceConfigurationTests {
  private let temporary: TemporaryDirectory
  private let registry: SchemaRegistry

  init() throws {
    temporary = try TemporaryDirectory()
    registry = try WorkspaceFixture.registry()
  }

  private func resolve(_ extra: String) throws -> ResolvedWorkspaceContext {
    try temporary.writeFile(
      "use-cases.yml",
      contents: WorkspaceFixture.configuration(extra: extra),
    )
    return try WorkspaceContextResolver.resolve(
      options: ResolveWorkspaceContextOptions(workspaceRoot: temporary.url.path),
      registry: registry,
    )
  }

  // MARK: - Verifiers

  private var verifiersConfiguration: String {
    """
    verifiers:
      default: vitest
      vitest:
        preset: js.vitest
      build:
        kind: script
        evidence_kind: command_result
        command:
          - make
          - build
        inputs:
          - Makefile
        timeout_seconds: 30
    """
  }

  @Test
  func `the default verifier id is split out of the entry map`() throws {
    let context = try resolve(verifiersConfiguration)

    #expect(context.verifiers.defaultVerifierIdentifier == "vitest")
    #expect(Set(context.verifiers.verifiers.keys) == ["vitest", "build"])
  }

  @Test
  func `the default key is never itself a verifier entry`() throws {
    let context = try resolve(verifiersConfiguration)

    #expect(context.verifiers.verifiers["default"] == nil)
  }

  @Test
  func `a preset entry keeps the preset it names`() throws {
    let context = try resolve(verifiersConfiguration)
    let entry = try #require(context.verifiers.verifiers["vitest"])

    #expect(entry.preset == "js.vitest")
    #expect(entry.kind == nil)
  }

  @Test
  func `a script entry keeps every field the schema allows`() throws {
    let context = try resolve(verifiersConfiguration)
    let entry = try #require(context.verifiers.verifiers["build"])

    #expect(entry.kind == "script")
    #expect(entry.evidenceKind == "command_result")
    #expect(entry.command == ["make", "build"])
    #expect(entry.inputs == ["Makefile"])
    #expect(entry.timeoutSeconds == 30)
  }

  @Test
  func `an entry survives round-tripping member for member`() throws {
    let context = try resolve(verifiersConfiguration)
    let entry = try #require(context.verifiers.verifiers["vitest"])

    #expect(entry.value == JSONObject([("preset", .string("js.vitest"))]))
  }

  @Test
  func `a verifiers section with entries but no default names none`() throws {
    let context = try resolve(
      """
      verifiers:
        vitest:
          preset: js.vitest
      """,
    )

    #expect(context.verifiers.defaultVerifierIdentifier == nil)
    #expect(Set(context.verifiers.verifiers.keys) == ["vitest"])
  }

  @Test
  func `an absent verifiers section resolves to nothing`() throws {
    let context = try resolve("")

    #expect(context.verifiers == ResolvedWorkspaceVerifiers())
  }

  @Test(arguments: [JSONValue.null, .array([]), .string("vitest"), .number(1)])
  func `a verifiers section that is not an object resolves to nothing`(raw: JSONValue) {
    #expect(ResolvedWorkspaceVerifiers.normalize(raw) == ResolvedWorkspaceVerifiers())
  }

  @Test
  func `an entry that is not an object is dropped, and the rest survive`() {
    let raw = JSONValue.object(JSONObject([
      ("default", .number(1)),
      ("broken", .string("not an object")),
      ("vitest", .object(JSONObject([("preset", .string("js.vitest"))]))),
    ]))

    let normalized = ResolvedWorkspaceVerifiers.normalize(raw)

    #expect(normalized.defaultVerifierIdentifier == nil)
    #expect(Set(normalized.verifiers.keys) == ["vitest"])
  }

  // MARK: - The release gate

  @Test
  func `a release gate requiring CI authority is carried through`() throws {
    let context = try resolve(
      """
      release_gate:
        required_authority: ci
      """,
    )
    let gate = try #require(context.releaseGate)

    #expect(gate.requiredAuthority == .continuousIntegration)
    #expect(gate.requiresProtectedReference == nil)
  }

  @Test
  func `a release gate requiring a protected ref is carried through`() throws {
    let context = try resolve(
      """
      release_gate:
        require_protected_ref: true
      """,
    )
    let gate = try #require(context.releaseGate)

    #expect(gate.requiredAuthority == nil)
    #expect(gate.requiresProtectedReference == true)
  }

  @Test
  func `a release gate asking for both is carried through whole`() throws {
    let context = try resolve(
      """
      release_gate:
        required_authority: ci
        require_protected_ref: true
      """,
    )

    #expect(
      context.releaseGate
        == WorkspaceReleaseGate(
          requiredAuthority: .continuousIntegration,
          requiresProtectedReference: true,
        ),
    )
  }

  @Test
  func `an empty release gate means no requirement at all`() throws {
    let context = try resolve("release_gate: {}")

    #expect(context.releaseGate == nil)
  }

  @Test
  func `a release gate that only turns things off means no requirement`() throws {
    let context = try resolve(
      """
      release_gate:
        require_protected_ref: false
      """,
    )

    #expect(context.releaseGate == nil)
  }

  @Test
  func `an absent release gate means no requirement`() throws {
    let context = try resolve("")

    #expect(context.releaseGate == nil)
  }

  // MARK: - The approval trust anchor

  @Test
  func `a keyring path is carried through`() throws {
    let context = try resolve(
      """
      approval_trust:
        keyring_path: keys/registry.json
      """,
    )
    let trust = try #require(context.approvalTrust)

    #expect(trust.keyringPath == "keys/registry.json")
    #expect(trust.keyring == nil)
    #expect(trust.publicKeys == nil)
  }

  @Test
  func `an inline keyring survives round-tripping untouched`() throws {
    let context = try resolve(
      """
      approval_trust:
        keyring:
          keyring_schema_id: ucase-public-key-registry-v1
          keys:
            - key_id: ci-key-1
              algorithm: ed25519
              public_key: pem
              valid_from: 2026-01-01T00:00:00Z
              valid_until: null
              status: active
      """,
    )
    let trust = try #require(context.approvalTrust)
    let keyring = try #require(trust.keyring?.objectValue)

    #expect(keyring.keys == ["keyring_schema_id", "keys"])
    #expect(keyring["keyring_schema_id"] == .string("ucase-public-key-registry-v1"))
    #expect(keyring["keys"]?.arrayValue?.count == 1)
    #expect(keyring["keys"]?.arrayValue?.first?["valid_until"] == .null)
  }

  @Test
  func `inline public keys survive round-tripping untouched`() throws {
    let context = try resolve(
      """
      approval_trust:
        public_keys:
          - key_id: ci-key-1
            algorithm: ed25519
            public_key: pem
            valid_from: 2026-01-01T00:00:00Z
            valid_until: null
            status: active
      """,
    )
    let trust = try #require(context.approvalTrust)
    let keys = try #require(trust.publicKeys)

    #expect(keys.count == 1)
    #expect(keys.first?["key_id"] == .string("ci-key-1"))
    #expect(keys.first?["status"] == .string("active"))
  }

  @Test
  func `an absent approval trust anchor pins nothing`() throws {
    let context = try resolve("")

    #expect(context.approvalTrust == nil)
  }

  @Test(arguments: [JSONValue.null, .array([]), .object(JSONObject())])
  func `a trust anchor pinning nothing resolves to nothing`(raw: JSONValue) {
    #expect(WorkspaceApprovalTrust.normalize(raw) == nil)
  }

  @Test
  func `a trust anchor whose members are the wrong type pins nothing`() {
    let raw = JSONValue.object(JSONObject([
      ("keyring_path", .number(1)),
      ("keyring", .string("nope")),
      ("public_keys", .object(JSONObject())),
    ]))

    #expect(WorkspaceApprovalTrust.normalize(raw) == nil)
  }

  @Test(arguments: [JSONValue.null, .array([]), .string("ci")])
  func `a release gate that is not an object resolves to nothing`(raw: JSONValue) {
    #expect(WorkspaceReleaseGate.normalize(raw) == nil)
  }
}
