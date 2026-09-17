import Foundation
import Testing
import TestSupport
@testable import UseCasesCore

/// Access to the generated TypeScript presentation corpus, and the plan cases
/// rebuilt for real: the tree on disk, the matrix loaded (or its rows handed
/// straight to ``MatrixSnapshot``), the evidence replayed, the late files
/// written, then the plan selected against a fixed clock.
enum PresentationFixtures {
  static let golden: Result<JSONValue, SchemaError> = {
    do throws(SchemaError) {
      return try .success(JSONParser.parse(PresentationGoldenCorpus.json))
    } catch {
      return .failure(error)
    }
  }()

  /// The embedded schemas, which is what a shipped binary validates against.
  static let embeddedRegistry: Result<SchemaRegistry, SchemaError> = {
    do throws(SchemaError) {
      return try .success(SchemaRegistry())
    } catch {
      return .failure(error)
    }
  }()

  static func section(_ name: String) throws -> JSONValue {
    try #require(golden.get()[name], "corpus has no section \(name)")
  }

  static func goldenCase(
    _ name: String,
    in section: String,
  ) throws -> JSONValue {
    let cases = try #require(Self.section(section).arrayValue, "section \(section) is not a list")
    let match = cases.first { $0["name"]?.stringValue == name }
    return try #require(match, "corpus section \(section) has no case \(name)")
  }

  static func wire(_ value: JSONValue?) -> String {
    UseCasesFixtures.wire(value)
  }

  // MARK: - Plan cases

  /// Everything a plan case produced on the Swift side.
  struct PlanRun {
    let workspace: UseCasesFixtures.Workspace
    let outcome: Result<PresentationPlanResult, PresentationError>
  }

  /// A clock that always answers the same instant.
  struct FixedClock: PresentationClock {
    let instant: Double

    func milliseconds() -> Double {
      instant
    }
  }

  /// A clock a test fails on if planning reads it.
  struct UnreadClock: PresentationClock {
    func milliseconds() -> Double {
      Issue.record("the plan read the clock although the request carried generatedAt")
      return 0
    }
  }

  static func run(_ testCase: JSONValue) throws -> PlanRun {
    let workspace = try UseCasesFixtures.Workspace(tree: testCase["tree"])
    let context = try workspace.context()
    let matrix = try testCase["rows"].map { rows in
      try rowsMatrix(rows, diagnostics: testCase["matrix_diagnostics"], context: context)
    } ?? UseCaseMatrixLoader.load(context: context, registry: UseCasesFixtures.registry.get())
    let evidence = try EvidenceReplay.replay(context: context)
    let restore = try writeLateEntries(testCase["after"], in: workspace)
    defer {
      restore()
    }
    let request = try request(testCase["request"])
    let clock: any PresentationClock = testCase["clock_milliseconds"]?.numberValue
      .map { instant in
        FixedClock(instant: instant)
      } ?? UnreadClock()
    let mode = try UseCasesFixtures.string(testCase, "mode")
    let outcome = Result { () throws(PresentationError) -> PresentationPlanResult in
      if mode == "showcase" {
        return try PresentationPlanner.selectShowcasePlan(
          context: context,
          matrix: matrix,
          evidence: evidence,
          request: request,
          clock: clock,
        )
      }
      return try PresentationPlanner.selectWalkthroughPlan(
        context: context,
        matrix: matrix,
        evidence: evidence,
        request: request,
        clock: clock,
      )
    }
    return PlanRun(workspace: workspace, outcome: outcome)
  }

  /// The corpus request, as the TypeScript received it: an absent member is
  /// `undefined`.
  static func request(_ value: JSONValue?) throws -> PresentationPlanRequest {
    let value = try #require(value)
    return try PresentationPlanRequest(
      audience: UseCasesFixtures.string(value, "audience"),
      timeboxSeconds: #require(value["timeboxSeconds"]?.numberValue),
      maxItems: value["maxItems"]?.numberValue,
      hostSurface: value["hostSurface"]?.stringValue,
      changedPaths: (value["changedPaths"]?.arrayValue ?? []).compactMap(\.stringValue),
      requestedUseCaseIdentifiers: (value["requestedUseCaseIds"]?.arrayValue ?? [])
        .compactMap(\.stringValue),
      generatedAt: value["generatedAt"]?.stringValue,
      freshnessEvaluatedAt: value["freshnessEvaluatedAt"]?.stringValue,
      isStrict: value["strict"]?.boolValue ?? false,
    )
  }

  /// Rows handed to `buildMatrixSnapshot` as the generator built them.
  private static func rowsMatrix(
    _ rows: JSONValue,
    diagnostics: JSONValue?,
    context: ResolvedWorkspaceContext,
  ) throws -> MatrixSnapshot {
    let entries = try #require(rows.arrayValue)
    let candidates = try entries.enumerated().map { index, entry in
      let value = try #require(entry["value"]?.objectValue)
      let featureIdentifier = try UseCasesFixtures.string(entry, "feature_id")
      let semanticHash = try UseCasesFixtures.string(entry, "semantic_hash")
      #expect(SemanticHash.compute(.object(value)) == semanticHash)
      return LoadedUseCase(
        value: value,
        feature: JSONObject([
          ("id", .string(featureIdentifier)),
          ("name", .string("Fixture feature")),
          ("summary", .string("A fixture feature.")),
        ]),
        semanticHash: semanticHash,
        source: UseCaseSource(
          path: "use-cases/\(featureIdentifier).yml",
          jsonPointer: "/use_cases/\(index)",
          fileByteHash: PresentationPlanner.zeroHash,
        ),
      )
    }
    let injected = try (diagnostics?.arrayValue ?? []).map { diagnostic in
      try Diagnostic(
        code: UseCasesFixtures.string(diagnostic, "code"),
        severity: #require(DiagnosticSeverity(rawValue: UseCasesFixtures.string(
          diagnostic,
          "severity",
        ))),
        message: UseCasesFixtures.string(diagnostic, "message"),
      )
    }
    return MatrixSnapshot(
      context: context,
      files: [],
      candidates: candidates,
      diagnostics: injected,
    )
  }

  /// Files written after the context, matrix and evidence were read. Returns
  /// the undo for any permission change, so the tree can be removed.
  private static func writeLateEntries(
    _ entries: JSONValue?,
    in workspace: UseCasesFixtures.Workspace,
  ) throws -> () -> Void {
    var changedModes: [String] = []
    for entry in entries?.arrayValue ?? [] {
      let target = try workspace.absolute(UseCasesFixtures.string(entry, "path"))
      switch try UseCasesFixtures.string(entry, "kind") {
      case "file":
        try Data(UseCasesFixtures.string(entry, "text").utf8)
          .write(to: URL(fileURLWithPath: target))
      case "directory":
        try FileManager.default.createDirectory(atPath: target, withIntermediateDirectories: true)
      case "mode":
        let mode = try #require(entry["mode"]?.numberValue)
        #expect(chmod(target, mode_t(mode)) == 0)
        changedModes.append(target)
      default:
        Issue.record("unknown late entry")
      }
    }
    return {
      for path in changedModes {
        chmod(path, 0o644)
      }
    }
  }

  /// `validateBySchemaId`'s answer, as the generator recorded it.
  static func validationRecord(
    _ fileName: String,
    _ value: JSONValue,
  ) throws -> JSONValue {
    let result = try embeddedRegistry.get().validate(
      schemaIdentifier: SchemaRegistry.schemaIdentifier(forFileName: fileName),
      value: value,
      sourcePath: nil,
    )
    return .object(JSONObject([
      ("valid", .bool(result.isValid)),
      ("diagnostics", .array(result.diagnostics.map(\.jsonValue))),
    ]))
  }

  // MARK: - Items

  /// A plan item from its wire JSON: what a card case hands `renderCard`.
  static func item(_ value: JSONValue?) throws -> PresentationPlanItem {
    let value = try #require(value)
    let evidence = try #require(value["evidence_summary"])
    let freshness = try #require(value["freshness_summary"])
    return try PresentationPlanItem(
      planItemIdentifier: UseCasesFixtures.string(value, "plan_item_id"),
      presentationFormat: member(value, "presentation_format"),
      deliveryKind: member(value, "delivery_kind"),
      scenarioScope: member(value, "scenario_scope"),
      useCaseIdentifier: UseCasesFixtures.string(value, "use_case_id"),
      useCaseTitle: value["use_case_title"]?.stringValue,
      scenarioIdentifiers: strings(value["scenario_ids"]),
      useCaseContentHash: UseCasesFixtures.string(value, "use_case_content_hash"),
      estimatedSeconds: #require(value["estimated_seconds"]?.numberValue),
      estimateSource: member(value, "estimate_source"),
      setupSteps: strings(value["setup_steps"]),
      resolvedSteps: strings(value["resolved_steps"]),
      expectedObservations: strings(value["expected_observations"]),
      teardownSteps: strings(value["teardown_steps"]),
      requiredPermissions: strings(value["required_permissions"]),
      safetyConstraints: strings(value["safety_constraints"]),
      verificationPolicySnapshot: #require(value["verification_policy_snapshot"]?.objectValue),
      approvalPolicySnapshot: #require(value["approval_policy_snapshot"]?.objectValue),
      approvalResolutionRequiredAtRunStart: #require(
        value["approval_resolution_required_at_run_start"]?.boolValue as Bool?,
      ),
      requiredEvidence: [],
      evidenceSummary: ItemEvidenceSummary(
        readiness: member(evidence, "readiness"),
        activeEvidenceIdentifiers: strings(evidence["active_evidence_ids"]),
        basis: UseCasesFixtures.string(evidence, "basis"),
      ),
      freshnessSummary: ItemFreshnessSummary(
        state: member(freshness, "state"),
        basis: UseCasesFixtures.string(freshness, "basis"),
      ),
      knownGaps: [],
      selectionReasons: strings(value["selection_reasons"]),
      selectionReasonCodes: strings(value["selection_reason_codes"]),
      scoreComponents: ScoreComponents(changed: 0, value: nil, journey: nil, frequency: nil),
    )
  }

  /// The enum case a string member names.
  private static func member<Value: RawRepresentable>(
    _ value: JSONValue,
    _ key: String,
  ) throws -> Value where Value.RawValue == String {
    try #require(Value(rawValue: UseCasesFixtures.string(value, key)), "\(key) names no case")
  }

  /// The render result a card case supplied, or nil when it supplied none.
  static func renderResult(_ value: JSONValue?) throws -> RenderResult? {
    guard let value else {
      return nil
    }
    return try RenderResult(
      status: value["status"]?.stringValue.map { status in
        try #require(RenderStatus(rawValue: status))
      },
      got: value["got"]?.stringValue,
      evidenceIdentifier: value["evidenceId"]?.stringValue,
      answeredByHuman: value["answeredByHuman"]?.boolValue,
    )
  }

  private static func strings(_ value: JSONValue?) -> [String] {
    (value?.arrayValue ?? []).compactMap(\.stringValue)
  }
}
