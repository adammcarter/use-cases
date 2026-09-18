import Foundation
import Testing

/// The sharded workspace the three matrix/product.yml inventory suites build.
enum MatrixInventoryWorkspace {
  static let configuration = """
  schema_version: 1
  workspace_id: probe
  component_id: probe
  data_root: .
  use_cases_dir: use-cases
  evidence_dir: evidence
  demo_capsules_dir: demo-capsules
  showcase_runs_dir: showcase-runs
  default_workflow_mode: continuous

  """

  struct RowSpec {
    let identifier: String
    let value: String
    let journey: String
    let tags: [String]
  }

  static func rowYaml(_ row: RowSpec) -> String {
    """
      - id: \(row.identifier)
        title: Row \(row.identifier)
        lifecycle: active
        value_tier: \(row.value)
        journey_role: \(row.journey)
        usage_frequency: common
        tags: [\(row.tags.joined(separator: ", "))]
        actor: agent
        intent: Exist so the query has something to select.
        preconditions: [Nothing.]
        trigger: Nothing.
        scenarios:
          - id: \(row.identifier).golden_runs
            kind: steps
            steps: [Run it.]
            observable_outcomes: [It passes.]
        observable_outcomes: [It exists.]
        host_applicability:
          - host_surface: codex.cli
            supported: true
        verification_policy:
          mode: none
        approval_policy:
          mode: none

    """
  }

  static func make() throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("matrix-inventory")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: configuration)
    return directory
  }

  /// Write one feature shard: one feature summary, one or more rows.
  static func writeShard(
    _ directory: TemporaryDirectory,
    fileName: String,
    featureId: String,
    rows: [RowSpec],
  ) throws {
    try directory.writeFile(
      "use-cases/\(fileName)",
      contents: """
      schema_version: 1
      feature:
        id: \(featureId)
        name: \(featureId)
        summary: Summary for \(featureId).
      use_cases:
      \(rows.map(rowYaml).joined())
      """,
    )
  }

  static func addDamagedShard(
    _ directory: TemporaryDirectory,
    fileName: String = "broken.yml",
  ) throws {
    try directory.writeFile(
      "use-cases/\(fileName)",
      contents: "schema_version: 1\nfeature:\n  id: probe.broken\n",
    )
  }

  static func run(
    _ directory: TemporaryDirectory,
    _ arguments: [String],
  ) async throws -> CliBinary.JsonOutcome {
    try await CliBinary.resolved().runJson(
      arguments,
      cwd: directory.path,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
  }

  static func list(
    _ directory: TemporaryDirectory,
    _ arguments: [String] = [],
  ) async throws -> CliBinary.JsonOutcome {
    try await run(directory, ["matrix", "list", "--repo", "."] + arguments)
  }

  static func listedIdentifiers(_ outcome: CliBinary.JsonOutcome) -> [String] {
    (outcome.data["use_cases"]?.arrayValue ?? []).compactMap { row in
      row["id"]?.stringValue
    }
  }

  static func validate(_ directory: TemporaryDirectory) async throws -> CliBinary.JsonOutcome {
    try await run(directory, ["matrix", "validate", "--repo", "."])
  }

  static func status(_ directory: TemporaryDirectory) async throws -> CliBinary.JsonOutcome {
    try await run(directory, ["matrix", "status", "--repo", "."])
  }

  static let productRow = RowSpec(
    identifier: "probe.product.behavior",
    value: "critical",
    journey: "golden",
    tags: ["product-behavior"],
  )

  static let primitiveRow = RowSpec(
    identifier: "probe.primitive.op",
    value: "supporting",
    journey: "golden",
    tags: ["primitive"],
  )

  static func writeProductAndPrimitive(_ directory: TemporaryDirectory) throws {
    try writeShard(
      directory,
      fileName: "product.yml",
      featureId: "probe.product",
      rows: [productRow],
    )
    try writeShard(
      directory,
      fileName: "primitive.yml",
      featureId: "probe.primitive",
      rows: [primitiveRow],
    )
  }
}

/// The black-box oracle for matrix/product.yml, row `product_inventory`.
///
/// `MatrixProductTests` already covers coverage_by_value_and_journey and
/// integrity_degraded_nonfatal. claim_guardrails is parked pending an owner
/// decision and is deliberately left untouched here too.
///
/// Self-contained: a shared oracle file means one edit stales every row bound
/// to it.
struct MatrixProductInventoryTests {
  // golden_cli. A product-tier row and a primitive/support-tier row coexist in
  // one list, and each carries the value/journey metadata a selection is made
  // on.
  //
  // MEASURED GAP: the row also claims each row carries "usage and scenario
  // data". `matrix list --json` does not project usage_frequency or scenarios
  // at all — a row there is {id, title, feature_id, lifecycle, value_tier,
  // journey_role, source_path, semantic_hash, host_surfaces, tags}. That part
  // of the row is not something this CLI surface can prove; see the disabled
  // test below instead of a test that pretends it does.
  @Test
  func `product-level and primitive rows are listed together with their tiers`()
    async throws
  {
    let directory = try MatrixInventoryWorkspace.make()
    try MatrixInventoryWorkspace.writeProductAndPrimitive(directory)

    let listed = try await MatrixInventoryWorkspace.list(directory)
    #expect(listed.isOk == true)
    let identifiers = MatrixInventoryWorkspace.listedIdentifiers(listed)
    #expect(
      identifiers.contains("probe.product.behavior")
        && identifiers.contains("probe.primitive.op"),
      "the product row and the primitive row are both addressable",
    )

    for row in listed.data["use_cases"]?.arrayValue ?? [] {
      let identifier = row["id"]?.stringValue ?? "?"
      #expect(
        row["value_tier"]?.stringValue?.isEmpty == false,
        Comment(rawValue: "\(identifier) carries a value tier"),
      )
      #expect(
        row["journey_role"]?.stringValue?.isEmpty == false,
        Comment(rawValue: "\(identifier) carries a journey role"),
      )
    }

    // Selectable by id alone: the id string is all that was needed above, no
    // implementation file was read to find these rows.
    let product = (listed.data["use_cases"]?.arrayValue ?? []).first { row in
      row["id"]?.stringValue == "probe.product.behavior"
    }
    #expect(product?["value_tier"]?.stringValue == "critical")
  }

  /// `test.todo` in vitest; a disabled test carrying the same reason here.
  @Test(.disabled("""
  golden_cli — the row also claims each row carries usage and scenario data, but \
  `matrix list --json` never projects usage_frequency or scenarios (measured); no CLI \
  surface exposes them per row, so this part is not provable black-box
  """))
  func `golden_cli — usage and scenario data are not projected by any CLI surface`() {
    Issue.record("unreachable: this test is disabled")
  }

  // edge_primitive_rows_stay_supporting. There is no schema field that marks a
  // row "primitive" vs "product" — the distinction lives in value_tier. A
  // supporting-tier row stays addressable on its own, but a critical+golden
  // cut leaves it out, which is what "supporting proof rather than the whole
  // product map" means in practice.
  @Test
  func `a supporting-tier row stays addressable outside the critical cut`()
    async throws
  {
    let directory = try MatrixInventoryWorkspace.make()
    try MatrixInventoryWorkspace.writeProductAndPrimitive(directory)

    let critical = try await MatrixInventoryWorkspace.listedIdentifiers(
      MatrixInventoryWorkspace.list(directory, ["--value", "critical"]),
    )
    #expect(critical == ["probe.product.behavior"])
    #expect(
      !critical.contains("probe.primitive.op"),
      "the primitive row does not crowd the headline cut",
    )

    let supporting = try await MatrixInventoryWorkspace.listedIdentifiers(
      MatrixInventoryWorkspace.list(directory, ["--value", "supporting"]),
    )
    #expect(
      supporting == ["probe.primitive.op"],
      "but it is still directly retrievable as supporting proof",
    )
  }
}

/// The black-box oracle for matrix/product.yml, row
/// `sharded_human_readable_files`.
struct MatrixShardedFilesTests {
  static let alphaOne = MatrixInventoryWorkspace.RowSpec(
    identifier: "probe.alpha.one",
    value: "core",
    journey: "golden",
    tags: ["probe"],
  )

  static let alphaTwo = MatrixInventoryWorkspace.RowSpec(
    identifier: "probe.alpha.two",
    value: "core",
    journey: "edge",
    tags: ["probe"],
  )

  // golden_layout. Two feature shards, each with one feature summary and one
  // related row, validate together as a single matrix.
  @Test
  func `two feature shards validate together as one matrix`() async throws {
    let directory = try MatrixInventoryWorkspace.make()
    try MatrixInventoryWorkspace.writeShard(
      directory,
      fileName: "alpha.yml",
      featureId: "probe.alpha",
      rows: [Self.alphaOne],
    )
    try MatrixInventoryWorkspace.writeShard(
      directory,
      fileName: "beta.yml",
      featureId: "probe.beta",
      rows: [MatrixInventoryWorkspace.RowSpec(
        identifier: "probe.beta.two",
        value: "supporting",
        journey: "edge",
        tags: ["probe"],
      )],
    )

    let validated = try await MatrixInventoryWorkspace.validate(directory)
    #expect(validated.isOk == true)
    #expect(validated.data["valid"]?.boolValue == true)
    let files = validated.data["files"]?.arrayValue ?? []
    let paths = files.compactMap { file in
      file["path"]?.stringValue
    }.sorted()
    #expect(paths == ["use-cases/alpha.yml", "use-cases/beta.yml"])
    let allLoaded = files.allSatisfy { file in
      file["status"]?.stringValue == "loaded"
    }
    #expect(allLoaded)
    #expect(validated.data.at("counts.files_loaded")?.intValue == 2)
  }

  // bad_damaged_shard_is_named. Damaging one shard leaves the other loadable,
  // and validation names the damaged file rather than reporting a bare failure.
  @Test
  func `a damaged shard is named while its sibling still loads`() async throws {
    let directory = try MatrixInventoryWorkspace.make()
    try MatrixInventoryWorkspace.writeShard(
      directory,
      fileName: "alpha.yml",
      featureId: "probe.alpha",
      rows: [Self.alphaOne],
    )
    try MatrixInventoryWorkspace.addDamagedShard(directory)

    let validated = try await MatrixInventoryWorkspace.validate(directory)
    #expect(validated.isOk == false)
    #expect(validated.data["valid"]?.boolValue == false)
    let files = validated.data["files"]?.arrayValue ?? []
    let damaged = files.filter { file in
      file["status"]?.stringValue != "loaded"
    }.compactMap { file in
      file["path"]?.stringValue
    }
    #expect(damaged == ["use-cases/broken.yml"])
    let alpha = files.first { file in
      file["path"]?.stringValue == "use-cases/alpha.yml"
    }
    #expect(alpha?["status"]?.stringValue == "loaded")
  }

  // edge_one_feature_summary_per_file. Every row loaded from a given shard
  // reports that shard's own feature id, and no row crosses over to another
  // shard's feature id — one feature per file, observed through the rows it
  // produces.
  @Test
  func `rows loaded from one shard all share that shard's single feature id`()
    async throws
  {
    let directory = try MatrixInventoryWorkspace.make()
    try MatrixInventoryWorkspace.writeShard(
      directory,
      fileName: "alpha.yml",
      featureId: "probe.alpha",
      rows: [Self.alphaOne, Self.alphaTwo],
    )
    try MatrixInventoryWorkspace.writeShard(
      directory,
      fileName: "beta.yml",
      featureId: "probe.beta",
      rows: [MatrixInventoryWorkspace.RowSpec(
        identifier: "probe.beta.one",
        value: "supporting",
        journey: "golden",
        tags: ["probe"],
      )],
    )

    let listed = try await MatrixInventoryWorkspace.list(directory)
    var byFile: [String: Set<String>] = [:]
    for row in listed.data["use_cases"]?.arrayValue ?? [] {
      guard let path = row["source_path"]?.stringValue,
            let feature = row["feature_id"]?.stringValue
      else {
        continue
      }
      byFile[path, default: []].insert(feature)
    }
    #expect(byFile["use-cases/alpha.yml"] == ["probe.alpha"])
    #expect(byFile["use-cases/beta.yml"] == ["probe.beta"])
  }
}

/// The black-box oracle for matrix/product.yml, row `status_summary`.
struct MatrixStatusSummaryTests {
  static let alphaOne = MatrixShardedFilesTests.alphaOne

  // golden_report. Row counts, integrity state, and evidence coverage are all
  // readable from the one `matrix status` call.
  @Test
  func `matrix and evidence health are both readable from one command`()
    async throws
  {
    let directory = try MatrixInventoryWorkspace.make()
    try MatrixInventoryWorkspace.writeShard(
      directory,
      fileName: "alpha.yml",
      featureId: "probe.alpha",
      rows: [Self.alphaOne],
    )

    let statused = try await MatrixInventoryWorkspace.status(directory)
    #expect(statused.isOk == true)
    #expect(statused.data.at("matrix.counts.use_case_candidates")?.intValue == 1)
    #expect(statused.data.at("matrix.integrity.state")?.stringValue == "clean")
    #expect(statused.data.at("evidence.integrity.state")?.stringValue == "clean")
    #expect(statused.data.at("evidence.counts") != nil)
  }

  // bad_summary_is_never_a_cached_claim. Editing a use-case file and
  // immediately re-running status (no other command in between) must change
  // the reported counts — a stale number would mean the summary is cached
  // rather than derived from the files on disk.
  @Test
  func `editing a shard and re-running status immediately changes the counts`()
    async throws
  {
    let directory = try MatrixInventoryWorkspace.make()
    try MatrixInventoryWorkspace.writeShard(
      directory,
      fileName: "alpha.yml",
      featureId: "probe.alpha",
      rows: [Self.alphaOne],
    )

    let before = try await MatrixInventoryWorkspace.status(directory)
    #expect(before.data.at("matrix.counts.use_case_candidates")?.intValue == 1)

    try MatrixInventoryWorkspace.writeShard(
      directory,
      fileName: "alpha.yml",
      featureId: "probe.alpha",
      rows: [Self.alphaOne, MatrixShardedFilesTests.alphaTwo],
    )

    let after = try await MatrixInventoryWorkspace.status(directory)
    #expect(
      after.data.at("matrix.counts.use_case_candidates")?.intValue == 2,
      "the same file, changed on disk, is not answered from a cache",
    )
  }

  // edge_gaps_visible_without_a_full_plan_run. A damaged shard's integrity
  // gap shows up straight from `matrix status` — no `plan showcase` or
  // `plan walkthrough` needed to see it.
  @Test
  func `an integrity gap is visible from status alone, without running a plan`()
    async throws
  {
    let directory = try MatrixInventoryWorkspace.make()
    try MatrixInventoryWorkspace.writeShard(
      directory,
      fileName: "alpha.yml",
      featureId: "probe.alpha",
      rows: [Self.alphaOne],
    )
    try MatrixInventoryWorkspace.addDamagedShard(directory)

    let statused = try await MatrixInventoryWorkspace.status(directory)
    #expect(statused.isOk == false)
    #expect(statused.data.at("matrix.complete")?.boolValue == false)
    #expect(statused.data.at("matrix.integrity.state")?.stringValue == "partial")
    let blocking = statused.data.at("matrix.integrity.blocking_diagnostic_count")?.intValue ?? 0
    #expect(blocking > 0)
  }
}
