import Testing
@testable import UseCasesCore

/// Contracts the freshness corpus cannot state, because it compares a derived
/// status against a RECORDING rather than against the published schema, and
/// because every recorded keyless case runs in release mode behind the gate.
///
/// The TypeScript asserted `validateFreshnessStatus(status).ok` on each of its
/// own derivations; nothing in Swift validated a DERIVED status until here —
/// which is how two shapes that fail the frozen schema stayed unrecorded.
struct FreshnessContractTests {
  /// A derived row the frozen `ucase-freshness-status-v1` schema refuses. Both
  /// shapes were measured against the TypeScript, which produces byte-identical
  /// output and the same two messages, so they are ported behaviour, not a port
  /// fault (see the row 9 note in docs/rewrite/ladder-notes.md).
  private static func refusedShape(_ row: JSONValue) -> String? {
    if row["variant_local_status"] != nil {
      return "must NOT have additional properties"
    }
    if row["row_id"] == .string("") {
      return "must NOT have fewer than 1 characters"
    }
    return nil
  }

  @Test(arguments: MarkersFreshnessGoldenCorpus.freshnessCaseNames)
  func `a derived status validates unless it carries a shape the schema forbids`(
    caseName: String,
  ) throws {
    let input = try MarkersFreshnessFixtures.freshnessInput(caseName)

    let status = try Freshness.derive(input)

    let wire = status.jsonValue
    let refusals = try #require(wire["rows"]?.arrayValue).compactMap(Self.refusedShape)
    let result = MarkerSchemaValidation.validateFreshnessStatus(wire)
    if let refusal = refusals.first {
      #expect(result.isValid == false, "\(caseName) was expected to be refused")
      #expect(result.errors.contains { error in
        error.message == refusal
      }, "\(caseName): \(MarkersFreshnessFixtures.wire(result.jsonValue))")
    } else {
      #expect(result.isValid, "\(caseName): \(MarkersFreshnessFixtures.wire(result.jsonValue))")
    }
  }

  @Test
  func `a variant row and an empty row id are the only shapes the schema refuses`() throws {
    let variants = try Freshness.derive(MarkersFreshnessFixtures
      .freshnessInput("variants_all_verified"))
    let emptyIdentifier = try Freshness.derive(MarkersFreshnessFixtures
      .freshnessInput("hand_built_errors_empty_and_equivalent_slugs"))

    let variantResult = MarkerSchemaValidation.validateFreshnessStatus(variants.jsonValue)
    let emptyResult = MarkerSchemaValidation.validateFreshnessStatus(emptyIdentifier.jsonValue)

    #expect(variantResult.errors.map(\.instancePath) == ["/rows/0"])
    #expect(variantResult.errors.map(\.message) == ["must NOT have additional properties"])
    #expect(emptyResult.errors.map(\.instancePath) == ["/rows/0/row_id"])
    #expect(emptyResult.errors.map(\.message) == ["must NOT have fewer than 1 characters"])
  }

  @Test
  func `a missing trusted key is not corruption, so a keyless scan still exits zero`() throws {
    let materialized = try VerifyProveFixtures.materialized(
      "trusted_append_chains_signs_and_skips_fresh",
      in: "prove_cases",
    )
    defer {
      _ = materialized.directory
    }
    let context = try VerifyProveFixtures.context(root: materialized.root)
    for step in materialized.steps {
      let options = try #require(step["options"])
      _ = try ProveCommand.run(
        VerifyProveFixtures.proveOptions(options, context: context, root: materialized.root),
        registry: MarkerCommandsFixtures.registry.get(),
        runKeyLocation: VerifyProveFixtures.runKeyLocation(options, root: materialized.root),
        environment: [:],
      )
    }

    let withKey = try Self.scan(materialized, context: context, trustedKeyConfigured: true)
    let keyless = try Self.scan(materialized, context: context, trustedKeyConfigured: false)

    #expect(withKey.exitCode == 0)
    #expect(withKey.status.rows.contains { row in
      row.status == .fresh
    })
    // Nobody can check the signature, so no row is FRESH — but a proof nobody
    // can check is not a damaged ledger, and feature mode must not fail.
    #expect(keyless.exitCode == 0)
    #expect(keyless.evidenceValid)
    #expect(keyless.status.rows.allSatisfy { row in
      row.status != .fresh
    })
  }

  private static func scan(
    _ materialized: MaterializedCase,
    context: ResolvedWorkspaceContext,
    trustedKeyConfigured: Bool,
  ) throws -> ScanCommandResult {
    var options = try ScanCommandOptions(
      context: context,
      productRoot: context.workspaceRoot,
      bindingsPath: NodePath.join(context.dataRoot, ".use-cases", "bindings.jsonl"),
      evidencePath: NodePath.join(context.dataRoot, ".use-cases", "proofs.jsonl"),
      policyMode: .feature,
      publicKeyResolver: VerifyProveFixtures.resolver(trustedKeyConfigured),
      generatedAt: VerifyProveFixtures.string("generated_at"),
    )
    options.trustedKeyConfigured = trustedKeyConfigured
    options.repositoryWorkingDirectory = context.workspaceRoot
    return try ScanCommand.run(
      options,
      registry: MarkerCommandsFixtures.registry.get(),
      runKeyLocation: VerifyProveFixtures.runKeyLocation(
        .object(JSONObject()),
        root: materialized.root,
      ),
    )
  }
}

/// The one authority case the corpus cannot reach: a CI this build does not
/// recognise. Every recorded `local` case passes an EMPTY environment, so
/// nothing showed that a foreign CI's variables do not trip detection.
struct ForeignContinuousIntegrationTests {
  @Test(arguments: [
    ["CI": "true", "TRAVIS": "true"],
    ["CI": "1", "BUILDKITE": "true", "BUILDKITE_BRANCH": "main"],
    ["JENKINS_URL": "https://jenkins.example", "BUILD_NUMBER": "42"],
  ])
  func `an unrecognised CI is local and generic, not a detected authority`(
    environment: [String: String],
  ) {
    let authority = CiAuthority.detect(environment: environment)

    #expect(authority.type == .local)
    #expect(authority.provider == .generic)
    #expect(authority.runIdentifier == nil)
    #expect(authority.protectedReference == .omitted)
  }
}
