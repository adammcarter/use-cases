/// The text `use-cases init` writes, line for line as `init/scaffold.ts` renders it.
enum ScaffoldTemplates {
  static let configurationFile = "use-cases.yml"
  static let useCaseFile = "use-cases/example.yml"
  static let defaultVerifierIdentifier = "acceptance"
  static let exampleRowIdentifier = "example.feature.happy_path"
  static let javaScriptVitestSourceFile = "src/example.ts"
  static let javaScriptVitestTestFile = "tests/use-cases/\(exampleRowIdentifier).test.ts"

  /// A marker comment's opening, assembled here so no line of this file is
  /// itself a marker.
  private static let markerOpening = "//" + ": @use-case:"

  /// A verifier's YAML lines under `verifiers.acceptance`, and its summary.
  struct VerifierPlan {
    let yaml: [String]
    let summary: ScaffoldDefaultVerifier
  }

  static func defaultVerifier(for template: InitializationTemplate) -> VerifierPlan {
    func preset(_ identifier: String) -> VerifierPlan {
      VerifierPlan(
        yaml: ["    preset: \(identifier)", "    evidence_kind: test_result"],
        summary: ScaffoldDefaultVerifier(
          identifier: defaultVerifierIdentifier,
          kind: .preset,
          preset: identifier,
          command: nil,
        ),
      )
    }
    switch template {
    case .javaScriptVitest:
      return preset("js.vitest")
    case .pythonPytest:
      return preset("python.pytest")
    case .goTest:
      return preset("go.test")
    case .generic:
      let command = ["false", "TODO-replace-with-your-verifier-command-for-{slug}"]
      let quoted = command.map { part in
        JSONWriter.encode(.string(part))
      }
      return VerifierPlan(
        yaml: [
          "    # TODO: replace this placeholder with the real command that verifies a row.",
          "    # `{slug}` is substituted with the row id at run time. It exits non-zero",
          "    # until you configure it, so a placeholder can never mint a passing proof.",
          "    kind: script",
          "    evidence_kind: test_result",
          "    command: [\(quoted.joined(separator: ", "))]",
        ],
        summary: ScaffoldDefaultVerifier(
          identifier: defaultVerifierIdentifier,
          kind: .script,
          preset: nil,
          command: command,
        ),
      )
    }
  }

  static func configuration(
    componentIdentifier: String,
    verifier: VerifierPlan,
  ) -> String {
    ([
      "schema_version: 1",
      "workspace_id: \(componentIdentifier)",
      "component_id: \(componentIdentifier)",
      "data_root: .",
      "use_cases_dir: use-cases",
      "evidence_dir: evidence",
      "demo_capsules_dir: demo-capsules",
      "showcase_runs_dir: showcase-runs",
      "default_workflow_mode: continuous",
      "# Verifiers map a row's required_verifiers id to a real command. `default` is",
      "# used by any row that does not name its own verifier. See docs/cli.md.",
      "verifiers:",
      "  default: \(defaultVerifierIdentifier)",
      "  \(defaultVerifierIdentifier):",
    ] + verifier.yaml + [""]).joined(separator: "\n")
  }

  //: @use-case:plugin.init.vends_sample_matrix#code
  static let exampleUseCase = [
    "schema_version: 1",
    "# A worked example of one use-case row. Copy it for your first real row, then",
    "# delete this one. One row is one behaviour; its scenarios are its tests \u{2014} each",
    "# scenario below becomes exactly one test, written before the code.",
    "feature:",
    "  id: example.feature",
    "  name: Example feature",
    "  summary: A sample use case vended by `use-cases init` \u{2014} "
      + "copy its shape for your own rows.",
    "metadata:",
    "  owner: unassigned",
    "  lifecycle: active",
    "use_cases:",
    "  - id: example.feature.happy_path",
    "    title: Example happy path",
    "    # planned while the row is agreed but unproven; active once tests are green",
    "    # and both the test and the code are wrapped in this row's markers.",
    "    lifecycle: active",
    "    # How much the product depends on this: critical | core | supporting | long_tail.",
    "    value_tier: core",
    "    # Where it sits in the user's journey: golden | alternate | edge | negative | failure.",
    "    journey_role: golden",
    "    # How often users hit it: common | occasional | rare.",
    "    usage_frequency: common",
    "    tags: [example]",
    "    # Files the behaviour lives in. `use-cases bind` wraps the exact span with a marker.",
    "    source_refs:",
    "      - kind: file",
    "        path: src/example.ts",
    "    # Who triggers the behaviour: user | agent | script | system.",
    "    actor: user",
    "    # What they are trying to achieve, in one sentence.",
    "    intent: Demonstrate the use-cases row shape so you can copy it.",
    "    # What must already be true before the trigger.",
    "    preconditions:",
    "      - The project is set up.",
    "    # The event that starts the behaviour.",
    "    trigger: The user performs the example action.",
    "    # One golden path, then the bad paths and the edge cases. Each scenario is",
    "    # one test; a test that proves nothing here is a scenario to write first.",
    "    scenarios:",
    "      - id: example.feature.happy_path.golden",
    "        kind: steps",
    "        steps:",
    "          - Perform the example action with valid input.",
    "          - Observe the expected result.",
    "      - id: example.feature.happy_path.bad_input",
    "        kind: steps",
    "        steps:",
    "          - Perform the example action with invalid input.",
    "          - Observe a clear error and no side effect.",
    "      - id: example.feature.happy_path.edge_empty",
    "        kind: steps",
    "        steps:",
    "          - Perform the example action with empty input.",
    "          - Observe the documented empty-input behaviour.",
    "    # What a person can see when the behaviour holds \u{2014} the acceptance criteria.",
    "    observable_outcomes:",
    "      - The expected result is visible to the user.",
    "      - Invalid input is refused with a clear message.",
    "    host_applicability:",
    "      - host_surface: codex.cli",
    "        supported: true",
    "    # Which verifier (from use-cases.yml) has to pass for this row to count.",
    "    verification_policy:",
    "      mode: requirements",
    "      requirements:",
    "        - evidence_kind: test_result",
    "          required_verifiers: [\(defaultVerifierIdentifier)]",
    "          minimum_count: 1",
    "    # Whether a human must sign this row off in a showcase before release.",
    "    approval_policy:",
    "      mode: none",
    "",
  ].joined(separator: "\n")
  //: @use-case:end plugin.init.vends_sample_matrix#code

  /// The js-vitest runnable example: a marked source file and its test.
  static func templateFiles(
    for template: InitializationTemplate,
    javaScriptVitestRunCommand: String,
  ) -> [(relativePath: String, body: String)] {
    guard template == .javaScriptVitest else {
      return []
    }
    return [
      (javaScriptVitestSourceFile, javaScriptVitestSource),
      (javaScriptVitestTestFile, javaScriptVitestTest(runCommand: javaScriptVitestRunCommand)),
    ]
  }

  static let javaScriptVitestSource = [
    "// A tiny, self-contained module an adopter might own. The exported",
    "// function below is the implementation the use-case row",
    "// `\(exampleRowIdentifier)` describes. It is wrapped in a Use Cases",
    "// marker span (the `@use-case` start/end comments) so the matrix can bind",
    "// the row to exactly these source lines. Replace it with your own code.",
    "",
    "\(markerOpening)\(exampleRowIdentifier)",
    "export function greet(name: string): string {",
    "  const trimmed = name.trim();",
    #"  if (trimmed === "") {"#,
    #"    throw new Error("name must not be empty");"#,
    "  }",
    "  return `Hello, ${trimmed}!`;",
    "}",
    "\(markerOpening)end \(exampleRowIdentifier)",
    "",
  ].joined(separator: "\n")

  static func javaScriptVitestTest(runCommand: String) -> String {
    [
      "// Acceptance test for the `\(exampleRowIdentifier)` use-case row.",
      "//",
      "// Run this file directly with",
      "//   \(runCommand)",
      "// or let `use-cases verify` invoke the `js.vitest` preset for the row. Replace",
      "// these assertions as you replace the example row with your own use case.",
      #"import { describe, expect, test } from "vitest";"#,
      #"import { greet } from "../../src/example.js";"#,
      "",
      "describe(\"\(exampleRowIdentifier)\", () => {",
      #"  test("greets a named user", () => {"#,
      #"    expect(greet("Ada")).toBe("Hello, Ada!");"#,
      "  });",
      "",
      #"  test("trims surrounding whitespace", () => {"#,
      #"    expect(greet("  Ada  ")).toBe("Hello, Ada!");"#,
      "  });",
      "",
      #"  test("rejects an empty name", () => {"#,
      #"    expect(() => greet("   ")).toThrow();"#,
      "  });",
      "});",
      "",
    ].joined(separator: "\n")
  }

  /// The lockfiles that pick the package manager, first match wins.
  static let packageManagerLockfiles: [(packageManager: String, lockfile: String)] = [
    ("pnpm", "pnpm-lock.yaml"),
    ("yarn", "yarn.lock"),
    ("npm", "package-lock.json"),
    ("bun", "bun.lockb"),
  ]

  static func javaScriptVitestRunCommand(packageManager: String?) -> String {
    let testPath = javaScriptVitestTestFile
    return switch packageManager {
    case "pnpm": "pnpm -s vitest run \(testPath)"
    case "yarn": "yarn vitest run \(testPath)"
    case "npm": "npm exec -- vitest run \(testPath)"
    case "bun": "bun x vitest run \(testPath)"
    default: "npx vitest run \(testPath)"
    }
  }

  // MARK: - Hooks

  static let hookBlockMarker = "# use-cases:"

  private static let useCasesLookup = [
    "# The plugin puts use-cases on PATH in Claude sessions; "
      + "elsewhere set USE_CASES to <plugin>/bin/use-cases.",
    #"use_cases="${"# +
      #"USE_CASES:-$(command -v use-cases 2>/dev/null || true)}""#,
    #"if [ -z "$use_cases" ]; then"#,
    #"  echo "pre-commit: use-cases not found \#u{2014} install the Use Cases plugin "# +
      #"(https://github.com/adammcarter/use-cases) or set USE_CASES=<plugin>/bin/use-cases" >&2"#,
    "  exit 0",
    "fi",
  ]

  static var preCommitBlock: [String] {
    [
      "\(hookBlockMarker) the matrix and its ledgers have to be well-formed to land at all.",
      #"if [ -f "$(git rev-parse --show-toplevel)/use-cases.yml" ]; then"#,
    ] + useCasesLookup.map { line in
      "  " + line
    } + [
      #"  root="$(git rev-parse --show-toplevel)""#,
      #"  "$use_cases" matrix validate --repo "$root" --json >/dev/null \"#,
      #"    || { echo "pre-commit: use-case matrix invalid \#u{2014} "# +
        #"run: use-cases matrix validate --repo ." >&2; exit 1; }"#,
      #"  key=""; [ -f "$root/.use-cases/trusted-ci-public-key.pem" ] "# +
        #"&& key="--public-key $root/.use-cases/trusted-ci-public-key.pem""#,
      #"  "$use_cases" validate-ledger --repo "$root" $key --json >/dev/null \"#,
      #"    || { echo "pre-commit: use-case ledger invalid \#u{2014} "# +
        #"run: use-cases validate-ledger --repo ." >&2; exit 1; }"#,
      "  # A marker and its binding that disagree is INVALID; stale is fine here.",
      #"  if "$use_cases" scan --repo "$root" --json 2>/dev/null "# +
        #"| grep -Eq '"status": *"INVALID"'; then"#,
      #"    echo "pre-commit: a use-case marker and its binding disagree \#u{2014} "# +
        #"run: use-cases scan --repo ." >&2"#,
      "    exit 1",
      "  fi",
      "fi",
    ]
  }

  static var prePushBlock: [String] {
    [
      "\(hookBlockMarker) say which bound rows this push touches and where they stand. "
        + "Advisory only.",
      #"if [ -f "$(git rev-parse --show-toplevel)/use-cases.yml" ]; then"#,
    ] + useCasesLookup.map { line in
      replacingFirst("pre-commit:", with: "pre-push:", in: "  " + line)
    } + [
      #"  root="$(git rev-parse --show-toplevel)""#,
      #"  "$use_cases" impact --repo "$root" 2>/dev/null || true"#,
      #"  "$use_cases" scan --repo "$root" 2>/dev/null | tail -n 20 || true"#,
      "fi",
      "exit 0",
    ]
  }

  /// `String.prototype.replace` with a string pattern: the first occurrence.
  private static func replacingFirst(
    _ target: String,
    with replacement: String,
    in text: String,
  ) -> String {
    guard let index = CodeUnitText.firstIndex(of: target, in: text) else {
      return text
    }
    let units = Array(text.utf16)
    let targetLength = target.utf16.count
    return CodeUnits
      .string(units[..<index] + Array(replacement.utf16) + units[(index + targetLength)...])
  }
}

/// Substring search over UTF-16 code units, as `indexOf` and `includes` search.
enum CodeUnitText {
  static func firstIndex(
    of target: String,
    in text: String,
  ) -> Int? {
    let units = Array(text.utf16)
    let needle = Array(target.utf16)
    guard needle.count <= units.count else {
      return nil
    }
    for start in 0 ... (units.count - needle.count) where units[start ..< start + needle.count]
      .elementsEqual(needle)
    {
      return start
    }
    return nil
  }

  static func hasSuffixLineFeed(_ text: String) -> Bool {
    text.utf16.last == 0x0A
  }
}
