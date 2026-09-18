import Foundation
import Testing

/// The workspace both matrix/product.yml suites build: four rows spread across
/// both axes the row selects on.
enum MatrixProductWorkspace {
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
    let name: String
    let value: String
    let journey: String
  }

  static let rows = [
    RowSpec(name: "crit_golden", value: "critical", journey: "golden"),
    RowSpec(name: "core_edge", value: "core", journey: "edge"),
    RowSpec(name: "supp_negative", value: "supporting", journey: "negative"),
    RowSpec(name: "core_failure", value: "core", journey: "failure"),
  ]

  static func rowYaml(_ spec: RowSpec) -> String {
    """
      - id: probe.core.\(spec.name)
        title: Row \(spec.name)
        lifecycle: active
        value_tier: \(spec.value)
        journey_role: \(spec.journey)
        usage_frequency: common
        tags: [probe]
        actor: agent
        intent: Exist so the query has something to select.
        preconditions: [Nothing.]
        trigger: Nothing.
        scenarios:
          - id: probe.core.\(spec.name).golden_runs
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
    let directory = try TemporaryDirectory("matrix-product")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: configuration)
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: """
      schema_version: 1
      feature:
        id: probe.core
        name: Probe
        summary: Probe.
      use_cases:
      \(rows.map(rowYaml).joined())
      """,
    )
    return directory
  }

  /// Damage a SECOND shard, leaving the first intact.
  static func addDamagedShard(_ directory: TemporaryDirectory) throws {
    try directory.writeFile(
      "use-cases/broken.yml",
      contents: "schema_version: 1\nfeature:\n  id: probe.broken\n",
    )
  }

  static func environment(_ directory: TemporaryDirectory) -> [String: String] {
    ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"]
  }

  static func list(
    _ directory: TemporaryDirectory,
    _ arguments: [String] = [],
  ) async throws -> CliBinary.JsonOutcome {
    try await CliBinary.resolved().runJson(
      ["matrix", "list", "--repo", "."] + arguments,
      cwd: directory.path,
      environment: environment(directory),
    )
  }

  static func listedRows(_ outcome: CliBinary.JsonOutcome) -> [OracleJson] {
    outcome.data["use_cases"]?.arrayValue ?? []
  }

  static func listedIdentifiers(_ outcome: CliBinary.JsonOutcome) -> [String] {
    listedRows(outcome).compactMap { row in
      row["id"]?.stringValue
    }
  }

  static func validate(_ directory: TemporaryDirectory) async throws -> CliBinary.JsonOutcome {
    try await CliBinary.resolved().runJson(
      ["matrix", "validate", "--repo", "."],
      cwd: directory.path,
      environment: environment(directory),
    )
  }
}

/// The black-box oracle for matrix/product.yml, row
/// `coverage_by_value_and_journey`.
///
/// Self-contained: a shared oracle file means one edit stales every row bound
/// to it.
struct MatrixProductCoverageTests {
  // golden_selection. High-value rows separate cleanly from the long tail,
  // which is what makes a short showcase selectable at all.
  @Test
  func `filtering by value tier and journey role returns sound, non-empty slices`()
    async throws
  {
    let directory = try MatrixProductWorkspace.make()

    let critical = try await MatrixProductWorkspace.list(directory, ["--value", "critical"])
    #expect(critical.isOk == true)
    let criticalRows = MatrixProductWorkspace.listedRows(critical)
    #expect(!criticalRows.isEmpty)
    for row in criticalRows {
      #expect(
        row["value_tier"]?.stringValue == "critical",
        "a filtered slice contains only what was asked for",
      )
    }

    let golden = try await MatrixProductWorkspace.list(directory, ["--journey-role", "golden"])
    let goldenRows = MatrixProductWorkspace.listedRows(golden)
    #expect(!goldenRows.isEmpty)
    for row in goldenRows {
      #expect(row["journey_role"]?.stringValue == "golden")
    }
  }

  // edge_deeper_cuts_reach_beyond_golden. A walkthrough needs the alternate,
  // edge, negative and failure rows a showcase would leave out — and the two
  // cuts must genuinely differ, or the distinction is decorative.
  @Test
  func `a deeper cut reaches the edge, negative and failure rows golden omits`()
    async throws
  {
    let directory = try MatrixProductWorkspace.make()

    let all = try await MatrixProductWorkspace.listedIdentifiers(
      MatrixProductWorkspace.list(directory),
    )
    let goldenOnly = try await MatrixProductWorkspace.listedIdentifiers(
      MatrixProductWorkspace.list(directory, ["--journey-role", "golden"]),
    )

    for role in ["edge", "negative", "failure"] {
      let slice = try await MatrixProductWorkspace.listedIdentifiers(
        MatrixProductWorkspace.list(directory, ["--journey-role", role]),
      )
      #expect(!slice.isEmpty, Comment(rawValue: "\(role) rows must be selectable"))
      for identifier in slice {
        #expect(
          !goldenOnly.contains(identifier),
          Comment(
            rawValue: "\(identifier) is \(role), so a golden cut must not contain it",
          ),
        )
      }
    }
    #expect(
      goldenOnly.count < all.count,
      "the golden cut is narrower than the whole matrix",
    )
  }
}

/// The black-box oracle for matrix/product.yml, row
/// `integrity_degraded_nonfatal`.
struct MatrixProductIntegrityTests {
  // golden_partial. Damaged YAML must not bring the system down: the valid
  // rows stay addressable.
  @Test
  func `a damaged shard keeps its valid siblings addressable`() async throws {
    let directory = try MatrixProductWorkspace.make()
    let before = try await MatrixProductWorkspace.listedRows(
      MatrixProductWorkspace.list(directory),
    ).count
    #expect(before == MatrixProductWorkspace.rows.count)

    try MatrixProductWorkspace.addDamagedShard(directory)

    let after = try await MatrixProductWorkspace.listedRows(
      MatrixProductWorkspace.list(directory),
    )
    #expect(after.count == before, "valid rows survive a damaged neighbour")
  }

  // bad_damage_is_surfaced_not_swallowed. Tolerating damage is never hiding it,
  // and the damaged FILE is named rather than left to be hunted.
  @Test
  func `integrity goes partial and the damaged file is named`() async throws {
    let directory = try MatrixProductWorkspace.make()
    let clean = try await MatrixProductWorkspace.validate(directory)
    #expect(clean.data.at("integrity.state")?.stringValue == "clean")

    try MatrixProductWorkspace.addDamagedShard(directory)
    let validated = try await MatrixProductWorkspace.validate(directory)

    #expect(validated.isOk == false)
    #expect(validated.data["valid"]?.boolValue == false)
    // `partial` is the distinction this row exists for. An EMPTY matrix reports
    // `unusable` instead — degraded and unusable are not the same state.
    #expect(validated.data.at("integrity.state")?.stringValue == "partial")
    #expect(
      validated.data.at("integrity.populated")?.boolValue == true,
      "partial still means populated",
    )

    let files = validated.data["files"]?.arrayValue ?? []
    let damaged = files.filter { file in
      file["status"]?.stringValue != "loaded"
    }
    let names = damaged.compactMap { file in
      file["path"]?.stringValue?.split(separator: "/").last.map(String.init)
    }
    #expect(names.contains("broken.yml"))
    let loaded = files.contains { file in
      file["status"]?.stringValue == "loaded"
    }
    #expect(loaded, "the good shard still loads")
  }

  // edge_partial_integrity_precedes_any_claim. The state is reported before
  // anything downstream could read the rows as complete coverage.
  @Test
  func `the partial state is visible in the result that still carries the rows`()
    async throws
  {
    let directory = try MatrixProductWorkspace.make()
    try MatrixProductWorkspace.addDamagedShard(directory)

    let validated = try await MatrixProductWorkspace.validate(directory)
    #expect((validated.data.at("counts.files_loaded")?.intValue ?? 0) > 0)
    #expect((validated.data.at("counts.files_excluded")?.intValue ?? 0) > 0)
    #expect(
      (validated.data.at("integrity.blocking_diagnostic_count")?.intValue ?? 0) > 0,
      "the damage is counted, not merely mentioned",
    )
  }
}
