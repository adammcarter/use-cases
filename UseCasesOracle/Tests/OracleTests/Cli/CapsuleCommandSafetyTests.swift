import Foundation
import Testing

/// The black-box oracle for capsule/demos.yml, row `runner_command_safety`.
struct CapsuleCommandSafetyTests {
  static func commandResults(_ outcome: CliBinary.JsonOutcome) -> [OracleJson] {
    outcome.data["command_results"]?.arrayValue ?? []
  }

  static func diagnosticCodes(_ outcome: CliBinary.JsonOutcome) -> [String] {
    (outcome.data["diagnostics"]?.arrayValue ?? []).compactMap { entry in
      entry["code"]?.stringValue
    }
  }

  // golden_command. Three properties at once, all only checkable by actually
  // running a command: it is not handed to a shell (a shell metacharacter is
  // passed through literally, not expanded), it runs from a working directory
  // resolved inside the repo, and its output is captured into the record.
  @Test
  func `a permitted command runs without a shell, from inside the repo`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.commandCapsule(
        executable: "node",
        argv: [
          "-e",
          "console.log(process.argv[1]); console.log(process.cwd())",
          "$(echo pwned)",
        ],
        workingDirectory: ".",
        expectedExitCodes: [0],
        permitted: true,
      ),
    )

    let performed = try await CapsuleDemosWorkspace.run(directory, [
      "capsule", "run", "--capsule", "capsule.probe.cmd",
      "--execute-commands", "--idempotency-key", "safety-golden",
    ])

    #expect(performed.isOk == true, Comment(rawValue: performed.standardOutput))
    let result = try #require(Self.commandResults(performed).first)
    let lines = (result["stdout"]?.stringValue ?? "")
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .split(separator: "\n")
      .map(String.init)
    #expect(
      lines.first == "$(echo pwned)",
      "a shell would have expanded $(...); no shell means it comes through literally",
    )
    #expect(lines.count > 1 && lines[1] == directory.realPath)
    #expect(result["matched_expected_exit_code"]?.boolValue == true)
  }

  // bad_unsafe_commands_do_not_run_by_default. Permission is required at BOTH
  // levels: the capsule must permit command execution, and the caller must
  // separately opt in with --execute-commands. Missing either one refuses to
  // run the command — checked here as two separate refusals.
  @Test
  func `a command step needs both the capsule's permission and the caller's`()
    async throws
  {
    let permitted = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      permitted,
      contents: CapsuleDemosWorkspace.commandCapsule(
        executable: "node",
        argv: ["-e", "1"],
        workingDirectory: ".",
        expectedExitCodes: [0],
        permitted: true,
      ),
    )
    // The capsule permits it, but the caller never asked for --execute-commands.
    let notRequested = try await CapsuleDemosWorkspace.run(permitted, [
      "capsule", "run", "--capsule", "capsule.probe.cmd",
      "--idempotency-key", "safety-not-requested",
    ])
    #expect(Self.commandResults(notRequested).isEmpty, "the command never ran")
    let pending = (notRequested.data["pending_steps"]?.arrayValue ?? []).contains { step in
      step["use_case_id"]?.stringValue == "probe.core.alpha"
        && step["reason"]?.stringValue == "command_execution_not_requested"
    }
    #expect(pending)
    #expect(notRequested.data.at("status.execution_status")?.stringValue != "completed")

    let unpermitted = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      unpermitted,
      contents: CapsuleDemosWorkspace.commandCapsule(
        executable: "node",
        argv: ["-e", "1"],
        workingDirectory: ".",
        expectedExitCodes: [0],
        permitted: false,
      ),
    )
    // The caller asks for --execute-commands, but the capsule never permitted it.
    let notPermitted = try await CapsuleDemosWorkspace.run(unpermitted, [
      "capsule", "run", "--capsule", "capsule.probe.cmd",
      "--execute-commands", "--idempotency-key", "safety-not-permitted",
    ])
    #expect(notPermitted.exitCode == 1)
    #expect(notPermitted.isOk == false)
    #expect(notPermitted.data["outcome"]?.stringValue == "blocked")
    #expect(notPermitted.data["run_id"]?.isNull == true, "a blocked run never starts")
    #expect(
      Self.diagnosticCodes(notPermitted).contains("capsule.command_execution_not_permitted"),
    )
  }

  // bad_working_directory_outside_the_repo. A capsule cannot point a command
  // at a working directory outside the workspace, no matter what permissions
  // it carries.
  @Test
  func `a working directory outside the repo is refused rather than resolved`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.commandCapsule(
        executable: "node",
        argv: ["-e", "1"],
        workingDirectory: "/tmp",
        expectedExitCodes: [0],
        permitted: true,
      ),
    )

    let blocked = try await CapsuleDemosWorkspace.run(directory, [
      "capsule", "run", "--capsule", "capsule.probe.cmd",
      "--execute-commands", "--idempotency-key", "safety-escape",
    ])

    #expect(blocked.exitCode == 4, "a cwd escape maps to its own exit code")
    #expect(blocked.isOk == false)
    #expect(blocked.data["outcome"]?.stringValue == "blocked")
    #expect(blocked.data["run_id"]?.isNull == true)
    #expect(Self.diagnosticCodes(blocked).contains("capsule.command_cwd_escape"))
  }

  // edge_output_is_bounded_and_local_state_does_not_leak. Two guarantees at
  // once: captured output cannot grow without bound, and the command does not
  // inherit the caller's whole environment (only a small, explicit allowlist),
  // so a secret sitting in the agent's own env cannot leak through a demo.
  @Test
  func `captured output is truncated and local environment does not leak`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()
    let script = """
    process.stdout.write('SECRET_LOCAL_VAR=' + (process.env.SECRET_LOCAL_VAR || 'undefined') \
    + '\\n'); process.stdout.write('A'.repeat(50000))
    """
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.commandCapsule(
        executable: "node",
        argv: ["-e", script],
        workingDirectory: ".",
        expectedExitCodes: [0],
        permitted: true,
      ),
    )

    let performed = try await CapsuleDemosWorkspace.run(
      directory,
      [
        "capsule", "run", "--capsule", "capsule.probe.cmd",
        "--execute-commands", "--idempotency-key", "safety-bounded",
      ],
      extraEnvironment: ["SECRET_LOCAL_VAR": "leaked-secret-value"],
    )
    let result = try #require(Self.commandResults(performed).first)
    let stdout = result["stdout"]?.stringValue ?? ""

    #expect(stdout.hasPrefix("SECRET_LOCAL_VAR=undefined"))
    #expect(
      !stdout.contains("leaked-secret-value"),
      "the local env var never reached the command",
    )
    #expect(
      stdout.hasSuffix("[truncated]"),
      "output beyond the cap is truncated, not silently grown",
    )
    #expect(stdout.count < 50000)
  }
}

/// The black-box oracle for capsule/demos.yml, row `stale_reference_warning`.
struct CapsuleStaleReferenceTests {
  // golden_validate. Whatever a capsule has to report about its references,
  // it reports through `capsule plan` — which only reads and reasons, and
  // never runs anything — before `capsule run` is ever invoked. This test
  // grows the matrix (a sibling row is added, as happens over the life of a
  // real feature file) and confirms the capsule keeps planning cleanly from
  // that read-only path.
  //
  // NOTE: the row's own step text says "validate the capsule", but
  // `capsule validate` only checks a capsule file's own schema — it does not
  // check whether the use-case/scenario ids it references still resolve
  // (confirmed empirically: validate stays ok/diagnostics-empty even when a
  // referenced row is later removed). Reference resolution is reported by
  // `capsule plan`, which is what this test exercises instead.
  @Test
  func `capsule plan reports reference health without ever running the capsule`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.smokeCapsule,
    )
    let sibling = """
      - id: probe.core.beta
        title: Beta
        lifecycle: active
        value_tier: supporting
        journey_role: alternate
        usage_frequency: rare
        actor: agent
        intent: A sibling row added later, unrelated to the capsule.
        preconditions: [Nothing.]
        trigger: Nothing.
        scenarios:
          - id: probe.core.beta.golden_runs
            kind: steps
            steps: [Do it.]
            observable_outcomes: [It works.]
        observable_outcomes: [It exists.]
        host_applicability:
          - host_surface: codex.cli
            supported: true
        verification_policy:
          mode: none
        approval_policy:
          mode: none

    """
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: CapsuleDemosWorkspace.matrixAlpha + sibling,
    )

    let planned = try await CapsuleDemosWorkspace.run(
      directory,
      ["capsule", "plan", "--capsule", "capsule.probe.smoke"],
    )

    #expect(planned.isOk == true, Comment(rawValue: planned.standardOutput))
    #expect(planned.data.at("plan_result.outcome")?.stringValue == "generated")
    let diagnostics = planned.data["diagnostics"]?.arrayValue ?? []
    #expect(diagnostics.isEmpty)
  }

  // bad_missing_row_reference. Remove the row a capsule references (the
  // matrix must stay schema-complete, so a sibling row takes its place) and
  // confirm the capsule is reported as broken rather than performed.
  @Test
  func `a capsule pointing at a missing row is reported as unrunnable`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.smokeCapsule,
    )
    try directory.writeFile(
      "use-cases/probe.yml",
      contents: CapsuleDemosWorkspace.matrixAlpha.replacingOccurrences(
        of: "probe.core.alpha",
        with: "probe.core.other",
      ),
    )

    let planned = try await CapsuleDemosWorkspace.run(
      directory,
      ["capsule", "plan", "--capsule", "capsule.probe.smoke"],
    )
    #expect(planned.data.at("plan_result.outcome")?.stringValue == "no_eligible_items")
    #expect(planned.data.at("plan_result.plan")?.isNull == true)
    #expect(planned.data.at("plan_result.candidate_summary.eligible")?.intValue == 0)

    let performed = try await CapsuleDemosWorkspace.run(directory, [
      "capsule", "run", "--capsule", "capsule.probe.smoke",
      "--idempotency-key", "stale-missing",
    ])
    #expect(
      performed.isOk == false,
      "a capsule that cannot resolve its row is never run",
    )
    #expect(performed.data["outcome"]?.stringValue == "blocked")
    #expect(performed.data["run_id"]?.isNull == true)
    let written = performed.data["events_written"]?.arrayValue ?? []
    #expect(written.isEmpty)
  }

  // edge_semantically_changed_row. A capsule stores only ids, never a copy of
  // the row's content, so it cannot drift: every plan re-resolves the row's
  // CURRENT title, steps and content hash from the matrix as it stands right
  // now.
  @Test
  func `changing a referenced row's meaning is reflected immediately`()
    async throws
  {
    let directory = try CapsuleDemosWorkspace.make()
    try CapsuleDemosWorkspace.writeCapsule(
      directory,
      contents: CapsuleDemosWorkspace.smokeCapsule,
    )
    let before = try await CapsuleDemosWorkspace.run(
      directory,
      ["capsule", "plan", "--capsule", "capsule.probe.smoke"],
    )
    let beforeItem = CapsuleDemosWorkspace.planItems(before).first

    let changed = CapsuleDemosWorkspace.matrixAlpha
      .replacingOccurrences(of: "title: Alpha", with: "title: Alpha renamed")
      .replacingOccurrences(
        of: "steps: [Do it.]",
        with: "steps: [Do something entirely different now.]",
      )
    try directory.writeFile("use-cases/probe.yml", contents: changed)

    let after = try await CapsuleDemosWorkspace.run(
      directory,
      ["capsule", "plan", "--capsule", "capsule.probe.smoke"],
    )
    let afterItem = CapsuleDemosWorkspace.planItems(after).first

    #expect(afterItem?["use_case_title"]?.stringValue == "Alpha renamed")
    let steps = (afterItem?["resolved_steps"]?.arrayValue ?? []).compactMap { step in
      step.stringValue
    }
    #expect(steps == ["Do something entirely different now."])
    #expect(
      afterItem?["use_case_content_hash"] != beforeItem?["use_case_content_hash"],
      "content hash moves with the row's real content",
    )
  }
}
