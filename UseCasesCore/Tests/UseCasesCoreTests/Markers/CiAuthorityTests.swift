import Testing
@testable import UseCasesCore

/// The CI-neutral provenance record signed into a proof event. The environment
/// is an input, never read from the process, so every case is deterministic.
struct CiAuthorityTests {
  private func override(_ name: String) -> ProtectedReference? {
    switch name {
    case "absent": nil
    case "undefined": .omitted
    case "null": .unknown
    default: .known(name == "true")
    }
  }

  @Test(arguments: MarkersLedgerGoldenCorpus.ciAuthorityCaseNames)
  func `detection emits the TypeScript's authority block`(caseName: String) throws {
    let entry = try MarkersLedgerFixtures.entry(caseName, in: "ci_authority")
    var environment: [String: String] = [:]
    for pair in try #require(entry["environment"]?.objectValue).pairs {
      environment[pair.key] = pair.value.stringValue
    }
    let overrideName = try MarkersLedgerFixtures.string(entry, "override")

    let authority = CiAuthority.detect(
      environment: environment,
      protectedReferenceOverride: override(overrideName),
    )

    #expect(try MarkersLedgerFixtures.wire(authority.jsonValue)
      == MarkersLedgerFixtures.string(entry, "wire"))
  }

  /// `protected_ref` has three states on the wire: absent, null, or a boolean.
  @Test
  func `protected ref keeps all three wire states`() {
    let omitted = CiAuthority.detect(environment: [:])
    let unknown = CiAuthority.detect(environment: ["GITHUB_ACTIONS": "true"])
    let known = CiAuthority.detect(
      environment: ["GITHUB_ACTIONS": "true"],
      protectedReferenceOverride: .known(true),
    )

    #expect(omitted.jsonValue["protected_ref"] == nil)
    #expect(unknown.jsonValue["protected_ref"] == .null)
    #expect(known.jsonValue["protected_ref"] == .bool(true))
  }
}
