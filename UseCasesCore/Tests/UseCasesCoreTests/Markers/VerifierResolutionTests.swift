import Testing
@testable import UseCasesCore

/// The verifier presets and the verifier resolver: which command verifies a
/// row. The resolved verifiers feed the verification context hash embedded in
/// every proof, so each answer is pinned to what the TypeScript returned.
struct VerifierResolutionTests {
  @Test
  func `the preset ids are the TypeScript's, in its order`() throws {
    let expected = try MarkersFixtures.strings(MarkersFreshnessFixtures.root(), "preset_ids")

    #expect(VerifierPresetIdentifier.allCases.map(\.rawValue) == expected)
  }

  @Test(arguments: MarkersFreshnessGoldenCorpus.presetCaseNames)
  func `a preset expands exactly as the TypeScript expands it`(caseName: String) throws {
    let entry = try MarkersFreshnessFixtures.entry(caseName, in: "presets")
    let preset = try MarkersFreshnessFixtures.string(entry, "preset")

    let expansion = try VerifierPresets.expand(
      presetIdentifier: preset,
      slug: MarkersFreshnessFixtures.string(entry, "slug"),
      variant: entry["variant"]?.stringValue,
    )

    #expect(try MarkersFreshnessFixtures.wire(expansion.jsonValue)
      == MarkersFreshnessFixtures.wire(#require(entry["expansion"])))
    #expect(try (VerifierPresetIdentifier(identifier: preset) != nil)
      == #require(entry["is_preset_id"]?.boolValue))
  }

  @Test
  func `only the four runner presets are test suites`() throws {
    for entry in try MarkersFreshnessFixtures.section("test_suite_presets") {
      let preset = entry["preset"]?.stringValue

      #expect(
        try VerifierPresets
          .isTestSuitePreset(preset) == #require(entry["is_test_suite"]?.boolValue),
        "\(preset ?? "nil")",
      )
    }
  }

  @Test(arguments: MarkersFreshnessGoldenCorpus.resolverCaseNames)
  func `a row's verifiers resolve as the TypeScript resolves them`(caseName: String) throws {
    let entry = try MarkersFreshnessFixtures.entry(caseName, in: "resolver")

    let resolved = try VerifierResolver.resolveRowVerifiers(
      slug: MarkersFreshnessFixtures.string(entry, "slug"),
      variant: entry["variant"]?.stringValue,
      verificationPolicy: MarkersFreshnessFixtures.policy(entry),
      workspace: MarkersFreshnessFixtures.workspace(entry["workspace"]),
    )

    #expect(try MarkersFreshnessFixtures.wire(.array(resolved.map(\.jsonValue)))
      == MarkersFreshnessFixtures.wire(#require(entry["resolved"])))
  }

  @Test
  func `the default convention id is the TypeScript's`() throws {
    #expect(try VerifierResolver.defaultConventionVerifierIdentifier
      == MarkersFreshnessFixtures.string(
        MarkersFreshnessFixtures.root(),
        "default_convention_verifier_id",
      ))
  }
}
