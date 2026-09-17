import Testing
@testable import UseCasesCore

/// The freshness state machine: the object `uc scan` emits. Every corpus case is
/// the TypeScript's whole output, compared byte for byte — key order, absent
/// members and `null` members included.
struct FreshnessTests {
  @Test(arguments: MarkersFreshnessGoldenCorpus.freshnessCaseNames)
  func `the freshness object is the TypeScript's, byte for byte`(caseName: String) throws {
    let entry = try MarkersFreshnessFixtures.entry(caseName, in: "freshness")
    let input = try MarkersFreshnessFixtures.freshnessInput(caseName)

    let status = try Freshness.derive(input)

    #expect(try MarkersFreshnessFixtures.wire(status.jsonValue)
      == MarkersFreshnessFixtures.string(entry, "wire"))
  }

  @Test
  func `the default tool is the product's own name and version`() throws {
    let input = try MarkersFreshnessFixtures.freshnessInput("fresh_row")

    let status = try Freshness.derive(input)

    #expect(status.tool == ProductVersion.versionInfo())
    #expect(status.jsonValue["tool"] == .object(JSONObject([
      ("name", .string(ProductVersion.productName)),
      ("version", .string(ProductVersion.version)),
    ])))
  }

  /// Four rows: a required FRESH row, a SUSPECT row, a required UNPROVEN row
  /// and an INVALID row. Each predicate keys off one field of the context, so
  /// the blocks it produces show that field was handed over for every row.
  @Test(arguments: [
    ("row", ["alpha.c"]),
    ("status", ["alpha.b"]),
    ("required", ["alpha.a", "alpha.c"]),
    ("invalid", ["alpha.d"]),
  ])
  func `a custom predicate is asked about each row with that row's own facts`(
    field: String,
    expectedBlocked: [String],
  ) throws {
    var input = try MarkersFreshnessFixtures.freshnessInput("custom_mode_always_false")
    input.customPolicy = switch field {
    case "row": { context in context.rowIdentifier == "alpha.c" }
    case "status": { context in context.status == .suspect }
    case "required": { context in context.requiredForRelease }
    default: { context in context.isInvalid }
    }

    let status = try Freshness.derive(input)

    #expect(status.rows.filter(\.policyBlock).map(\.rowIdentifier) == expectedBlocked)
    #expect(status.summary.policyBlocked == expectedBlocked.count)
  }

  @Test
  func `in custom mode the predicate alone decides, even for an INVALID row`() throws {
    var input = try MarkersFreshnessFixtures.freshnessInput("custom_mode_always_false")

    input.customPolicy = { _ in false }
    let never = try Freshness.derive(input)
    input.customPolicy = nil
    let fallback = try Freshness.derive(input)

    #expect(never.rows.contains { row in
      row.status == .invalid
    })
    #expect(never.rows.allSatisfy { row in
      !row.policyBlock
    })
    #expect(fallback.rows.filter(\.policyBlock).map(\.status) == [.invalid])
  }

  @Test(arguments: [
    "feature_mode_ignores_a_custom_predicate",
    "release_mode_ignores_a_custom_predicate",
  ])
  func `feature and release modes never consult the predicate`(caseName: String) throws {
    var input = try MarkersFreshnessFixtures.freshnessInput(caseName)
    input.customPolicy = { _ in true }
    let withPredicate = try Freshness.derive(input)
    input.customPolicy = nil
    let withoutPredicate = try Freshness.derive(input)

    #expect(withPredicate == withoutPredicate)
    #expect(withPredicate.rows.contains { row in
      !row.policyBlock
    })
  }

  @Test
  func `custom mode never applies the release gate`() throws {
    var input = try MarkersFreshnessFixtures.freshnessInput("release_gate_ci_no_authority_block")
    input.policyMode = .custom
    input.customPolicy = { _ in false }

    let status = try Freshness.derive(input)
    let required = try #require(status.rows.first { row in
      row.requiredForRelease
    })

    #expect(required.status == .fresh)
    #expect(required.reasons.isEmpty)
    #expect(!required.policyBlock)
  }

  @Test
  func `a row outside the TypeScript's domain is refused`() {
    let policies: [(String, JSONValue)] = [
      ("verification_policy", .null),
      ("approval_policy", .null),
    ]

    #expect(FreshnessInputRow(fields: JSONObject([("row_id", .string("a.b"))] + policies)) != nil)
    #expect(FreshnessInputRow(fields: JSONObject([("row_id", .number(1))] + policies)) == nil)
    #expect(FreshnessInputRow(fields: JSONObject([
      ("row_id", .string("a.b")),
      ("verification_policy", .null),
    ])) == nil)
    #expect(FreshnessInputRow(fields: JSONObject([
      ("row_id", .string("a.b")),
      ("approval_policy", .null),
    ])) == nil)
    #expect(FreshnessInputRow(fields: JSONObject([
      ("row_id", .string("a.b")),
      ("variants", .array([.object(JSONObject([("title", .string("no key"))]))])),
    ] + policies)) == nil)
  }

  @Test
  func `a proof event outside the TypeScript's domain is refused`() throws {
    let entry = try MarkersFreshnessFixtures.entry("fresh_row", in: "freshness")
    let event = try #require(entry["evidence"]?.arrayValue?.first?.objectValue)
    #expect(FreshnessProofEvent(json: .object(event)) != nil)

    for key in ["producer", "row", "verification", "bindings", "created_at"] {
      var broken = event
      broken[key] = nil
      #expect(FreshnessProofEvent(json: .object(broken)) == nil, "\(key)")
    }
    var badItem = event
    badItem["bindings"] = .object(JSONObject([("items", .array([.string("item")]))]))
    #expect(FreshnessProofEvent(json: .object(badItem)) == nil)
    #expect(FreshnessProofEvent(json: .array([])) == nil)
  }
}
