import Foundation
import Testing

/// The black-box oracle for lifecycle/signals.yml, row
/// `impact_leads_with_the_union`.
struct LifecycleImpactUnionTests {
  /// A committed single-row workspace with one edit applied to its source.
  static func editedWorkspace(
    replacing old: String,
    with new: String,
  ) async throws -> SignalsWorkspace.Workspace {
    let workspace = try await SignalsMultiRow.make(.init(rows: ["alpha"]))
    try await SignalsMultiRow.git(workspace.directory, ["init", "-q", "."])
    try await SignalsMultiRow.git(
      workspace.directory,
      ["config", "user.email", "probe@example.com"],
    )
    try await SignalsMultiRow.git(workspace.directory, ["config", "user.name", "Probe"])
    try await SignalsMultiRow.git(workspace.directory, ["add", "-A"])
    try await SignalsMultiRow.git(workspace.directory, ["commit", "-qm", "base"])
    let source = try workspace.directory.readFile("src/alpha.ts")
    try workspace.directory.writeFile(
      "src/alpha.ts",
      contents: source.replacingOccurrences(of: old, with: new),
    )
    return workspace
  }

  // golden_touched_not_hit. Editing a bound file BELOW its span hits no span,
  // and the headline must still count it.
  @Test
  func `the headline counts span-hit and file-touched rows together`() async throws {
    let workspace = try await Self.editedWorkspace(replacing: "return 2;", with: "return 3;")
    let impacted = try await SignalsWorkspace.run(workspace, ["impact", "--repo", "."])

    let hit = impacted.data["impacted"]?.arrayValue ?? []
    #expect(hit.isEmpty)
    let touched = (impacted.data["touched"]?.arrayValue ?? []).compactMap { row in
      row["row_id"]?.stringValue
    }
    #expect(touched == ["probe.core.alpha"])
    #expect(impacted.data["summary"]?.stringValue?.contains("1 touched") == true)
  }

  // bad_never_reports_nothing_impacted. The failure this row exists to stop: an
  // agent reads the headline, sees nothing, and skips re-verifying.
  @Test
  func `it never reports nothing impacted while a bound file was touched`()
    async throws
  {
    let workspace = try await Self.editedWorkspace(replacing: "return 2;", with: "return 3;")
    let human = try await SignalsWorkspace.runHuman(workspace, ["impact", "--repo", "."])
    #expect(human.exitCode == 0)
    #expect(
      !OracleText.contains(
        "(?m)^0 behaviours? (may be )?impacted by your change$",
        in: human.standardOutput,
      ),
    )
    #expect(human.standardOutput.contains("re-verify"))
    #expect(human.standardOutput.contains("file-touched"))
  }

  // edge_touched_row_carries_the_same_command. Being conservative costs one
  // re-verify; being wrong ships a regression. So a touched row is told to
  // re-verify exactly as a span-hit row is.
  @Test
  func `a touched row is told to re-verify, the same as a span-hit row`()
    async throws
  {
    let touched = try await Self.editedWorkspace(replacing: "return 2;", with: "return 3;")
    let hit = try await Self.editedWorkspace(replacing: "return 1;", with: "return 9;")

    let touchedOut = try await SignalsWorkspace.runHuman(touched, ["impact", "--repo", "."])
      .standardOutput
    let hitOut = try await SignalsWorkspace.runHuman(hit, ["impact", "--repo", "."])
      .standardOutput

    #expect(touchedOut.contains("probe.core.alpha"))
    #expect(hitOut.contains("probe.core.alpha"))
    #expect(touchedOut.contains("re-verify"))
    #expect(hitOut.contains("re-verify"))
  }
}

/// The black-box oracle for lifecycle/signals.yml, row
/// `transient_output_stays_out_of_git`.
struct LifecycleTransientOutputTests {
  static let transient = ["showcase-runs/", ".use-cases/verification-results.jsonl"]

  // golden_fresh_repo. The tool must not break the adopter's own clean-tree
  // gate.
  @Test
  func `init gitignores its own transient output in a repo with no gitignore`()
    async throws
  {
    let repository = try await SignalsMultiRow.makeBareRepo()
    let initialised = try await SignalsWorkspace.run(repository, ["init", "--repo", "."])
    #expect(initialised.isOk == true, Comment(rawValue: initialised.standardOutput))

    let gitignore = try repository.directory.readFile(".gitignore")
    for entry in Self.transient {
      #expect(gitignore.contains(entry))
    }
  }

  // edge_existing_gitignore_is_appended_to. Never rewritten, never reordered.
  @Test
  func `an existing gitignore is appended to, never rewritten or reordered`()
    async throws
  {
    let original = "node_modules/\n*.log\n"
    let repository = try await SignalsMultiRow.makeBareRepo(gitignore: original)
    _ = try await SignalsWorkspace.run(repository, ["init", "--repo", "."])

    let gitignore = try repository.directory.readFile(".gitignore")
    #expect(gitignore.hasPrefix(original), "the adopter's entries keep their place")
    for entry in Self.transient {
      #expect(gitignore.contains(entry))
    }
  }

  // edge_rerun_does_not_duplicate. A second init is refused outright, which is
  // what makes duplicate entries impossible rather than merely unlikely.
  @Test
  func `a second init is refused, so the entries cannot accumulate`() async throws {
    let repository = try await SignalsMultiRow.makeBareRepo()
    _ = try await SignalsWorkspace.run(repository, ["init", "--repo", "."])
    let before = try repository.directory.readFile(".gitignore")

    let second = try await SignalsWorkspace.run(repository, ["init", "--repo", "."])
    #expect(second.isOk == false)
    #expect(second.envelope.diagnostics.encoded.contains("workspace_exists"))
    #expect(try repository.directory.readFile(".gitignore") == before)
    for entry in Self.transient {
      #expect(
        before.components(separatedBy: entry).count - 1 == 1,
        Comment(rawValue: "\(entry) must appear once"),
      )
    }
  }
}
