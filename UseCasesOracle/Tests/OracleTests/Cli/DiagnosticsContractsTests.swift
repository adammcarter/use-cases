import Foundation
import Testing

/// The workspace the diagnostics/contracts.yml suites build, at the scope
/// `diagnostics-contracts.test.ts` shares it.
enum DiagnosticsWorkspace {
  /// NOT an empty `use_cases: []` — that fails schema.minItems, leaving the
  /// matrix `unusable`, so anything that then calls `matrix validate` would be
  /// asserting against a workspace that can never be valid.
  static let seededMatrix = """
  schema_version: 1
  feature:
    id: probe.core
    name: Probe
    summary: Probe.
  use_cases:
    - id: probe.core.alpha
      title: Alpha
      lifecycle: active
      value_tier: core
      journey_role: golden
      usage_frequency: common
      actor: agent
      intent: Exist so the matrix is valid.
      preconditions: [Nothing.]
      trigger: Nothing.
      scenarios:
        - id: probe.core.alpha.golden_runs
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

  static func configuration(dataRoot: String) -> String {
    """
    schema_version: 1
    workspace_id: probe
    component_id: probe
    data_root: \(dataRoot)
    use_cases_dir: use-cases
    evidence_dir: evidence
    demo_capsules_dir: demo-capsules
    showcase_runs_dir: showcase-runs
    default_workflow_mode: continuous

    """
  }

  /// A workspace whose data root may sit somewhere other than the repo root.
  static func make(dataRoot: String = ".") throws -> TemporaryDirectory {
    let directory = try TemporaryDirectory("diagnostics")
    try directory.writeFile("use-cases.yml", contents: configuration(dataRoot: dataRoot))
    let matrixDirectory = dataRoot == "." ? "use-cases" : "\(dataRoot)/use-cases"
    try directory.makeDirectory(matrixDirectory)
    try directory.writeFile("\(matrixDirectory)/probe.yml", contents: seededMatrix)
    return directory
  }

  static func environment(_ directory: TemporaryDirectory) -> [String: String] {
    ["UC_RUN_KEY_FILE": directory.path + "/machine/run-key"]
  }

  static func run(
    _ directory: TemporaryDirectory,
    _ arguments: [String],
  ) async throws -> CliBinary.JsonOutcome {
    try await CliBinary.resolved().runJson(
      arguments,
      cwd: directory.path,
      environment: environment(directory),
    )
  }
}

//: @use-case:diagnostics.contracts.root_resolution#blackbox
/// The black-box oracle for diagnostics/contracts.yml, row `root_resolution`.
///
/// Four of the file's five rows are here. The fifth, missing_build_hint, is
/// deliberately absent: it fires on the path where the COMPILED CORE is
/// missing, and a shipped binary is self-contained so it never takes that path.
/// Driving it through the binary would mean dismantling the build, which
/// measures the harness rather than the behaviour.
///
/// Self-contained: a shared oracle file means one edit stales every row bound
/// to it.
struct DiagnosticsRootResolutionTests {
  // golden_doctor. The two roots are separate facts, not one path.
  @Test
  func `doctor roots reports the workspace root and the data root distinctly`()
    async throws
  {
    let directory = try DiagnosticsWorkspace.make()
    let doctored = try await DiagnosticsWorkspace.run(
      directory,
      ["doctor", "roots", "--repo", "."],
    )

    #expect(doctored.isOk == true)
    #expect(doctored.data["workspace_root"]?.stringValue?.isEmpty == false)
    #expect(doctored.data["data_root"]?.stringValue?.isEmpty == false)
    #expect(doctored.data["use_cases_root"]?.stringValue?.contains("use-cases") == true)
    #expect(
      doctored.data["provenance"] != nil,
      "where each root came from is reported too",
    )
  }

  // edge_separated_data_root_resolves. The monorepo and CI layouts this exists
  // for: the data root moves without breaking the paths built from it.
  @Test
  func `a data root below the repo root resolves, and the matrix path follows`()
    async throws
  {
    let directory = try DiagnosticsWorkspace.make(dataRoot: "sub")
    let doctored = try await DiagnosticsWorkspace.run(
      directory,
      ["doctor", "roots", "--repo", "."],
    )

    #expect(doctored.isOk == true)
    #expect(doctored.data["data_root"] != doctored.data["workspace_root"])
    #expect(doctored.data["data_root"]?.stringValue?.hasSuffix("/sub") == true)
    #expect(doctored.data["use_cases_root"]?.stringValue?.contains("/sub/use-cases") == true)

    // And the relocated root actually works, rather than merely being reported.
    let validated = try await DiagnosticsWorkspace.run(
      directory,
      ["matrix", "validate", "--repo", "."],
    )
    #expect(validated.data["valid"]?.boolValue == true)
  }

  // bad_unsafe_or_symlinked_root_is_refused. A data root that climbs out of the
  // repo is refused rather than silently followed.
  @Test
  func `a data root pointing outside the repo is refused`() async throws {
    let directory = try DiagnosticsWorkspace.make()
    try directory.writeFile(
      "use-cases.yml",
      contents: DiagnosticsWorkspace.configuration(dataRoot: "../escape"),
    )

    let doctored = try await DiagnosticsWorkspace.run(
      directory,
      ["doctor", "roots", "--repo", "."],
    )
    #expect(doctored.isOk == false)
    #expect(doctored.envelope.diagnostics.encoded.contains("workspace_config"))
  }
}

//: @use-case:end diagnostics.contracts.root_resolution#blackbox

//: @use-case:diagnostics.contracts.schema_contract_surface#blackbox
/// The black-box oracle for diagnostics/contracts.yml, row
/// `schema_contract_surface`.
struct DiagnosticsSchemaSurfaceTests {
  // golden_validate. The contract is enumerable and its fixtures validate, so
  // an integrator can depend on it.
  @Test
  func `schema list enumerates the published v1 schemas and fixtures validate`()
    async throws
  {
    let binary = try CliBinary.resolved()
    let listed = try await binary.runJson(["schema", "list"])
    #expect(listed.isOk == true)
    let schemas = listed.data["schemas"]?.arrayValue ?? []
    #expect(schemas.count > 20)
    for schema in schemas {
      #expect(
        schema["id"]?.stringValue?.hasPrefix("https://use-cases.dev/schemas/v1/") == true,
        "every schema is published under a versioned id",
      )
    }

    let fixtures = try await binary.runJson(["schema", "validate-fixtures"])
    #expect(fixtures.isOk == true)
    // Bound first: `#expect(!(x?.y ?? []).isEmpty)` expands to a property-access
    // check that evaluates the OPTIONAL and reports a false failure.
    let validated = fixtures.data["validated_schema_ids"]?.arrayValue ?? []
    #expect(!validated.isEmpty)
  }

  // edge_cli_and_mcp_validate_against_the_same_ids. The envelope every command
  // emits is itself one of the published schemas — one contract, not two.
  @Test
  func `the result envelope every command emits is one of the published schemas`()
    async throws
  {
    let binary = try CliBinary.resolved()
    let listed = try await binary.runJson(["schema", "list"])
    let identifiers = (listed.data["schemas"]?.arrayValue ?? []).compactMap { schema in
      schema["id"]?.stringValue
    }
    #expect(identifiers.contains("https://use-cases.dev/schemas/v1/cli-result.schema.json"))

    // And a real envelope carries the fields that schema describes.
    let versioned = try await binary.runJson(["version"])
    let fields = [
      "schema_version", "protocol_version", "command", "ok",
      "complete", "data", "diagnostics", "context",
    ]
    for field in fields {
      #expect(
        versioned.envelope.json[field] != nil,
        Comment(rawValue: "envelope must carry \(field)"),
      )
    }
  }

  // bad_a_drifted_result_fails_validation. The fixture set is the guard: if a
  // result shape drifts from its declared schema, this is what goes red.
  @Test
  func `validate-fixtures reports the fixture it checked, so drift can fail`()
    async throws
  {
    let fixtures = try await CliBinary.resolved().runJson(["schema", "validate-fixtures"])
    #expect(fixtures.isOk == true)
    #expect(
      fixtures.data["fixture"]?.stringValue?.isEmpty == false,
      "the checked fixture is named",
    )
    #expect(
      fixtures.envelope.diagnostics.arrayValue?.isEmpty == true,
      "a clean run reports no drift",
    )
  }
}

//: @use-case:end diagnostics.contracts.schema_contract_surface#blackbox

//: @use-case:diagnostics.contracts.identity_consistency#blackbox
/// The black-box oracle for diagnostics/contracts.yml, row
/// `identity_consistency`.
struct DiagnosticsIdentityTests {
  // golden_envelope.
  @Test(arguments: [["version"], ["schema", "list"]])
  func `every envelope reports the configured component id`(
    arguments: [String],
  ) async throws {
    let answered = try await CliBinary.resolved().runJson(arguments)
    #expect(
      answered.envelope.context["component_id"]?.stringValue == "use-cases",
      Comment(rawValue: "\(arguments.joined(separator: " ")) must report the component id"),
    )
  }

  // edge_unconfigured_workspace_uses_the_default. A workspace with no config
  // still reports use-cases rather than nothing or a stale name.
  @Test
  func `an unconfigured workspace still defaults to use-cases`() async throws {
    let bare = try TemporaryDirectory("unconfigured")
    let versioned = try await CliBinary.resolved().runJson(
      ["version", "--repo", "."],
      cwd: bare.path,
    )
    #expect(versioned.envelope.context["component_id"]?.stringValue == "use-cases")
  }

  // bad_no_stale_product_name_survives_anywhere. The rename this row exists to
  // protect: a published build must never leak the pre-rename name.
  @Test(arguments: [["version"], ["schema", "list"]])
  func `no envelope leaks the pre-rename product name`(arguments: [String]) async throws {
    let raw = try await CliBinary.resolved().runJson(arguments).envelope.json.encoded.lowercased()
    #expect(
      !raw.contains("ucase-matrix"),
      Comment(rawValue: "\(arguments.joined(separator: " ")) leaked a stale product name"),
    )
    #expect(!raw.contains("usecase-matrix"))
  }
}

//: @use-case:end diagnostics.contracts.identity_consistency#blackbox

//: @use-case:diagnostics.contracts.cli_self_documents#blackbox
/// The black-box oracle for diagnostics/contracts.yml, row
/// `cli_self_documents`.
struct DiagnosticsSelfDocumentingTests {
  // golden_usage. An agent can discover the surface from the CLI itself.
  @Test
  func `a bare invocation and --help both print usage listing the commands`()
    async throws
  {
    let binary = try CliBinary.resolved()
    let bare = try await binary.runJson([])
    #expect(bare.envelope.command == "help")
    #expect(
      bare.data["usage"]?.stringValue?.contains("use-cases <command>") == true,
      "the usage line is in the envelope",
    )

    let helped = try await binary.run(["--help"])
    #expect(helped.exitCode == 0)
    #expect(helped.standardOutput.contains("use-cases — the Use Cases CLI"))
    for command in ["scan", "verify", "bind"] {
      #expect(
        helped.standardOutput.contains(command),
        Comment(rawValue: "help must list \(command)"),
      )
    }
  }

  // bad_unrecognized_command_is_not_a_bare_refusal. An unknown command gets
  // usage, not a dead end.
  @Test
  func `an unrecognised command answers with usage naming what was not recognised`()
    async throws
  {
    let binary = try CliBinary.resolved()
    let refused = try await binary.runJson(["frobnicate"])
    #expect(refused.isOk == false)
    #expect(
      refused.envelope.command == "help",
      "it answers as help rather than command.unknown",
    )

    let human = try await binary.run(["frobnicate"])
    let printed = human.standardOutput + human.standardError
    #expect(printed.contains("frobnicate"))
    #expect(printed.contains("use-cases --help"))
  }
}

//: @use-case:end diagnostics.contracts.cli_self_documents#blackbox
