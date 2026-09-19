import Testing
@testable import UseCasesCore

/// The planner's small pieces against the TypeScript's own answers: plan ids,
/// path order, exclusion wording, plan hashes, the two string orders, the
/// format table and the profile digests.
struct PresentationHelperTests {
  private static func helpers(_ name: String) throws -> JSONValue {
    try #require(PresentationFixtures.section("helpers")[name])
  }

  @Test
  func `plan ids are derived from generatedAt exactly as the TypeScript derives them`() throws {
    let probes = try #require(Self.helpers("plan_ids").arrayValue)
    #expect(probes.count == 24)
    for probe in probes {
      let mode = try #require(PresentationMode(rawValue: UseCasesFixtures.string(probe, "mode")))
      let generatedAt = try UseCasesFixtures.string(probe, "generated_at")

      let identifier = PresentationSnapshot.planIdentifier(mode: mode, generatedAt: generatedAt)

      #expect(
        identifier == probe["plan_id"]?.stringValue,
        "generatedAt \(generatedAt.debugDescription)",
      )
    }
  }

  @Test
  func `changed paths are normalised and sorted by UTF-16 code unit`() throws {
    for probe in try #require(Self.helpers("normalized_paths").arrayValue) {
      let input = try #require(probe["input"]?.arrayValue).compactMap(\.stringValue)
      let expected = try #require(probe["output"]?.arrayValue).compactMap(\.stringValue)

      let output = PresentationPlanHelpers.normalizedPaths(input)

      #expect(output.map(\.utf16).map(Array.init) == expected.map(\.utf16).map(Array.init))
    }
  }

  @Test
  func `the unreachable timebox wording is ported, and every other code reads as the item cap`(
  ) throws {
    let useCase = LoadedUseCase(
      value: JSONObject([("id", .string("helpers.row"))]),
      feature: JSONObject([("id", .string("helpers"))]),
      semanticHash: PresentationPlanner.zeroHash,
      source: UseCaseSource(
        path: "use-cases/helpers.yml",
        jsonPointer: "/use_cases/0",
        fileByteHash: "",
      ),
    )
    for probe in try #require(Self.helpers("exclusions").arrayValue) {
      let reasonCode = try UseCasesFixtures.string(probe, "reason_code")

      let exclusion = PresentationCandidates.capacityExclusion(for: useCase, reasonCode: reasonCode)

      #expect(PresentationFixtures.wire(exclusion.jsonValue) == PresentationFixtures
        .wire(probe["exclusion"]))
    }
  }

  @Test
  func `the plan content hash drops only the volatile members`() throws {
    for probe in try #require(Self.helpers("plan_hashes").arrayValue) {
      let plan = try #require(probe["plan"]?.objectValue)

      #expect(
        PresentationPlanner.planContentHash(of: plan) == probe["hash"]?.stringValue,
        "\(probe["name"]?.stringValue ?? "")",
      )
    }
  }

  @Test
  func `locale and code-unit orders disagree on these keys, and each matches the TypeScript`(
  ) throws {
    let orders = try Self.helpers("orders")
    let keys = try #require(orders["keys"]?.arrayValue).compactMap(\.stringValue)
    let locale = try #require(orders["locale"]?.arrayValue).compactMap(\.stringValue)
    let codeUnit = try #require(orders["code_unit"]?.arrayValue).compactMap(\.stringValue)

    #expect(locale != codeUnit)
    let sortedByLocale = keys.sorted { left, right in
      PresentationScoring.localeCompare(left, right) < 0
    }
    #expect(sortedByLocale == locale)
    #expect(PresentationPlanHelpers.normalizedPaths(keys) == codeUnit)
  }

  @Test
  func `the comparator orders unsorted candidates at every level as the TypeScript does`() throws {
    let probes = try #require(Self.helpers("comparator_sorts").arrayValue)
    #expect(probes.count == 3)
    for probe in probes {
      let candidates = try #require(probe["candidates"]?.arrayValue).map { entry in
        try Self.candidate(entry)
      }
      let expected = try #require(probe["sorted_ids"]?.arrayValue).compactMap(\.stringValue)

      let sorted = PresentationScoring.sorted(candidates).map(\.useCase.identifier)

      #expect(sorted == expected, "\(probe["name"]?.stringValue ?? "")")
    }
  }

  private static func candidate(_ entry: JSONValue) throws -> PresentationCandidate {
    let scores = try #require(entry["score_components"])
    let rank = { (key: String) throws -> Int in
      try Int(#require(scores[key]?.numberValue))
    }
    return try PresentationCandidate(
      useCase: LoadedUseCase(
        value: JSONObject([("id", .string(UseCasesFixtures.string(entry, "use_case_id")))]),
        feature: JSONObject([("id", .string(UseCasesFixtures.string(entry, "feature_id")))]),
        semanticHash: PresentationPlanner.zeroHash,
        source: UseCaseSource(
          path: "use-cases/probe.yml",
          jsonPointer: "/use_cases/0",
          fileByteHash: "",
        ),
      ),
      isEligible: true,
      exclusion: nil,
      isChanged: false,
      scoreComponents: ScoreComponents(
        changed: rank("changed"),
        value: rank("value"),
        journey: rank("journey"),
        frequency: rank("frequency"),
      ),
      reasonCodes: [],
      reasons: [],
    )
  }

  @Test
  func `the format table and its projections match the TypeScript`() throws {
    let formats = try Self.helpers("formats")
    for entry in try #require(formats["metadata"]?.arrayValue) {
      let format = try #require(PresentationFormat(rawValue: UseCasesFixtures.string(
        entry,
        "format",
      )))
      let emoji = try UseCasesFixtures.string(entry, "emoji")
      #expect(Array(format.metadata.emoji.utf8) == Array(emoji.utf8))
      #expect(format.metadata.verb == entry["verb"]?.stringValue)
      #expect(format.metadata.descriptor == entry["descriptor"]?.stringValue)
      #expect(format.metadata.actor.rawValue == entry["actor"]?.stringValue)
    }
    for entry in try #require(formats["delivery_kinds"]?.arrayValue) {
      let format = try #require(PresentationFormat(rawValue: UseCasesFixtures.string(
        entry,
        "format",
      )))
      let base = try #require(DeliveryKind(rawValue: UseCasesFixtures.string(entry, "base")))
      #expect(format.deliveryKind(base: base).rawValue == entry["delivery_kind"]?.stringValue)
    }
    for entry in try #require(formats["defaults"]?.arrayValue) {
      let kind = try #require(DeliveryKind(rawValue: UseCasesFixtures.string(entry, "kind")))
      #expect(PresentationFormat.defaultFormat(for: kind).rawValue == entry["format"]?.stringValue)
    }
    for entry in try #require(formats["choices"]?.arrayValue) {
      let base = try #require(DeliveryKind(rawValue: UseCasesFixtures.string(entry, "base")))
      let chosen = try PresentationFormat.choose(
        baseDeliveryKind: base,
        needsUser: #require(entry["needs_user"]?.boolValue as Bool?),
        isContrast: #require(entry["is_contrast"]?.boolValue as Bool?),
      )
      #expect(chosen.rawValue == entry["format"]?.stringValue)
    }
  }

  @Test
  func `profile digests hash the TypeScript profile objects`() throws {
    let digests = try Self.helpers("profile_digests")

    #expect(SemanticHash.compute(SelectionProfile.showcase.digestValue) == digests["showcase"]?
      .stringValue)
    #expect(SemanticHash
      .compute(SelectionProfile.walkthrough.digestValue) == digests["walkthrough"]?.stringValue)
  }
}
