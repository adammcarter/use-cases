import Foundation
import Testing

/// The workspace both matrix/core.yml suites below build, at the scope
/// `matrix-core.test.ts` shares it: module scope inside one oracle file.
enum MatrixCoreWorkspace {
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

  /// A COMPLETE matrix. Mutation is refused outright against an incomplete one
  /// (`matrix.mutation_incomplete_matrix`), so a seed row has to be here first
  /// or every test below would measure that refusal instead of the behaviour.
  static let seedMatrix = """
  schema_version: 1
  feature:
    id: probe.core
    name: Probe
    summary: Probe.
  use_cases:
    - id: probe.core.seed
      title: Seed row
      lifecycle: active
      value_tier: core
      journey_role: golden
      usage_frequency: common
      actor: agent
      intent: Exist so the matrix is complete enough to mutate.
      preconditions: [Nothing.]
      trigger: Nothing.
      scenarios:
        - id: probe.core.seed.golden_runs
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

  static let newRow = """
  {"id":"probe.core.alpha","title":"Alpha","lifecycle":"planned",\
  "value_tier":"core","journey_role":"golden","usage_frequency":"common"}
  """

  static func retitled(_ title: String) -> String {
    newRow.replacingOccurrences(of: "\"title\":\"Alpha\"", with: "\"title\":\"\(title)\"")
  }

  static func make() throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("matrix-core")
    try directory.makeDirectory("use-cases")
    try directory.writeFile("use-cases.yml", contents: configuration)
    try directory.writeFile("use-cases/probe.yml", contents: seedMatrix)
    return directory
  }

  static func run(
    _ directory: TemporaryDirectory,
    _ arguments: [String],
  ) async throws -> CliBinary.JsonOutcome {
    let (command, rest) = (arguments[0], Array(arguments.dropFirst(2)))
    return try await CliBinary.resolved().runJson(
      [command, arguments[1], "--repo", "."] + rest,
      cwd: directory.path,
      environment: ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"],
    )
  }

  static func featureFile(_ directory: TemporaryDirectory) throws -> String {
    try directory.readFile("use-cases/probe.yml")
  }

  static func rowCount(_ directory: TemporaryDirectory) throws -> Int {
    let file = try featureFile(directory)
    return OracleText.matches("(?m)^ {2}- id: ", in: file).count
  }

  static func mutationCodes(_ outcome: CliBinary.JsonOutcome) -> [String] {
    (outcome.data["diagnostics"]?.arrayValue ?? []).compactMap { entry in
      entry["code"]?.stringValue
    }
  }
}

//: @use-case:matrix.core.validate#blackbox
/// The black-box oracle for matrix/core.yml, row `validate`.
///
/// These two rows are among the eight that carry `verification_policy: mode:
/// none` — no verifier at all, so `use-cases verify` has never had anything to
/// run for them.
///
/// Self-contained on purpose: a shared oracle file means one edit stales every
/// row bound to it.
struct MatrixCoreValidateTests {
  // golden_cli.
  @Test
  func `a clean workspace reports clean integrity`() async throws {
    let directory = try MatrixCoreWorkspace.make()
    let validated = try await MatrixCoreWorkspace.run(directory, ["matrix", "validate"])

    #expect(validated.data["valid"]?.boolValue == true)
    #expect(validated.data.at("integrity.state")?.stringValue == "clean")
    #expect(validated.envelope.diagnostics.arrayValue?.isEmpty == true)
  }

  // bad_a_damaged_matrix_is_never_clean. Tolerating damage elsewhere is a
  // separate behaviour; what must never happen is damage reading as health.
  @Test
  func `a damaged file is never reported as clean, and diagnostics say what is wrong`()
    async throws
  {
    let directory = try MatrixCoreWorkspace.make()
    try directory.writeFile(
      "use-cases/broken.yml",
      contents: "schema_version: 1\nfeature:\n  id: probe.core\n",
    )

    let validated = try await MatrixCoreWorkspace.run(directory, ["matrix", "validate"])
    #expect(validated.data["valid"]?.boolValue == false)
    #expect(validated.data.at("integrity.state")?.stringValue != "clean")
    #expect(
      !(validated.envelope.diagnostics.arrayValue ?? []).isEmpty,
      "the damage must be named",
    )
  }
}

//: @use-case:end matrix.core.validate#blackbox

//: @use-case:matrix.core.mutate#blackbox
/// The black-box oracle for matrix/core.yml, row `mutate`.
struct MatrixCoreMutateTests {
  // golden_upsert. A mutation returns before and after hashes so a caller can
  // see exactly what moved, and the matrix stays clean afterwards.
  @Test
  func `upsert adds a row, returns hashes, and leaves the matrix clean`() async throws {
    let directory = try MatrixCoreWorkspace.make()
    let before = try MatrixCoreWorkspace.rowCount(directory)

    let upserted = try await MatrixCoreWorkspace.run(directory, [
      "matrix", "upsert", "--file", "use-cases/probe.yml",
      "--use-case-json", MatrixCoreWorkspace.newRow,
    ])

    #expect(upserted.isOk == true, Comment(rawValue: upserted.standardOutput))
    #expect(upserted.data["status"]?.stringValue == "created")
    #expect(upserted.data["use_case_id"]?.stringValue == "probe.core.alpha")
    #expect(
      upserted.data["after_hash"]?.stringValue?.hasPrefix("sha256:") == true,
      "an accepted write reports the hash it produced",
    )
    #expect(try MatrixCoreWorkspace.rowCount(directory) == before + 1)

    let validated = try await MatrixCoreWorkspace.run(directory, ["matrix", "validate"])
    #expect(
      validated.data["valid"]?.boolValue == true,
      "the matrix stays structurally clean after an accepted write",
    )
  }

  // edge_upsert_lands_on_an_existing_row. Upsert means both; landing on an id
  // that exists updates it rather than adding a second copy.
  @Test
  func `upsert on an existing id updates it in place rather than duplicating`()
    async throws
  {
    let directory = try MatrixCoreWorkspace.make()
    _ = try await MatrixCoreWorkspace.run(directory, [
      "matrix", "upsert", "--file", "use-cases/probe.yml",
      "--use-case-json", MatrixCoreWorkspace.newRow,
    ])
    let afterFirst = try MatrixCoreWorkspace.rowCount(directory)

    let updated = try await MatrixCoreWorkspace.run(directory, [
      "matrix", "upsert", "--file", "use-cases/probe.yml",
      "--use-case-json", MatrixCoreWorkspace.retitled("Alpha retitled"),
    ])

    #expect(updated.data["status"]?.stringValue == "updated")
    #expect(updated.data["before_hash"] != updated.data["after_hash"])
    #expect(try MatrixCoreWorkspace.rowCount(directory) == afterFirst, "no duplicate row")
    #expect(try MatrixCoreWorkspace.featureFile(directory).contains("Alpha retitled"))
  }

  // golden_remove. Removal is a lifecycle transition, not a deletion: the
  // history of the row survives it.
  @Test
  func `remove is a soft lifecycle transition that preserves the row`() async throws {
    let directory = try MatrixCoreWorkspace.make()
    _ = try await MatrixCoreWorkspace.run(directory, [
      "matrix", "upsert", "--file", "use-cases/probe.yml",
      "--use-case-json", MatrixCoreWorkspace.newRow,
    ])
    let before = try MatrixCoreWorkspace.rowCount(directory)

    let removed = try await MatrixCoreWorkspace.run(directory, [
      "matrix", "remove", "--use-case", "probe.core.alpha", "--reason", "retired",
    ])

    #expect(removed.isOk == true)
    #expect(removed.data["status"]?.stringValue == "removed")
    #expect(
      try MatrixCoreWorkspace.rowCount(directory) == before,
      "the row is not physically deleted",
    )
    #expect(try MatrixCoreWorkspace.featureFile(directory).contains("lifecycle: removed"))
  }

  // bad_stale_expected_hash. A write cannot land on a matrix that moved
  // underneath it.
  @Test
  func `a stale --expected-hash blocks the write`() async throws {
    let directory = try MatrixCoreWorkspace.make()
    // The guard is documented as being FOR UPDATES: creating a row has no prior
    // hash to guard, so the flag is ignored there. The row has to exist first
    // or this measures a create, not a concurrency guard.
    _ = try await MatrixCoreWorkspace.run(directory, [
      "matrix", "upsert", "--file", "use-cases/probe.yml",
      "--use-case-json", MatrixCoreWorkspace.newRow,
    ])
    let fileBefore = try MatrixCoreWorkspace.featureFile(directory)

    let blocked = try await MatrixCoreWorkspace.run(directory, [
      "matrix", "upsert", "--file", "use-cases/probe.yml",
      "--use-case-json", MatrixCoreWorkspace.retitled("Alpha from a stale reader"),
      "--expected-hash",
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
    ])

    #expect(blocked.isOk == false)
    #expect(blocked.data["status"]?.stringValue == "blocked")
    #expect(MatrixCoreWorkspace.mutationCodes(blocked).contains("matrix.mutation_hash_mismatch"))
    #expect(
      try MatrixCoreWorkspace.featureFile(directory) == fileBefore,
      "a blocked write changes nothing",
    )
  }

  // bad_path_escape_or_damaged_matrix. Two ways a write must be refused, kept
  // in one scenario because both are "the target is not somewhere we may write".
  @Test
  func `a path escape is blocked, and so is any mutation of an incomplete matrix`()
    async throws
  {
    let directory = try MatrixCoreWorkspace.make()
    let escaped = try await MatrixCoreWorkspace.run(directory, [
      "matrix", "upsert", "--file", "../outside.yml",
      "--use-case-json", MatrixCoreWorkspace.newRow,
    ])
    #expect(escaped.isOk == false)
    #expect(escaped.data["status"]?.stringValue == "blocked")
    #expect(MatrixCoreWorkspace.mutationCodes(escaped).contains("matrix.mutation_path_escape"))

    // An incomplete matrix refuses mutation outright, so a damaged workspace
    // cannot be edited further into a worse state.
    let damaged = try MatrixCoreWorkspace.make()
    try damaged.writeFile(
      "use-cases/probe.yml",
      contents: "schema_version: 1\nfeature:\n  id: probe.core\n",
    )
    let blocked = try await MatrixCoreWorkspace.run(damaged, [
      "matrix", "upsert", "--file", "use-cases/probe.yml",
      "--use-case-json", MatrixCoreWorkspace.newRow,
    ])
    #expect(blocked.isOk == false)
    #expect(blocked.data["status"]?.stringValue == "blocked")
  }
}

//: @use-case:end matrix.core.mutate#blackbox
