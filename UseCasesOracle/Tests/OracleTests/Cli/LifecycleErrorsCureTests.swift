import Foundation
import Testing

/// The black-box oracle for lifecycle/signals.yml, row
/// `errors_hand_back_the_cure`.
struct LifecycleErrorsCureTests {
  /// A workspace where the row was renamed in BOTH the matrix and the marker.
  static func renamedWorkspace(
    from oldIdentifier: String,
    to newIdentifier: String,
  ) async throws -> SignalsWorkspace.Workspace {
    let workspace = try await SignalsMultiRow.make(.init(rows: [oldIdentifier]))
    let feature = try workspace.directory.readFile("use-cases/probe.yml")
    try workspace.directory.writeFile(
      "use-cases/probe.yml",
      contents: feature.replacingOccurrences(
        of: "probe.core.\(oldIdentifier)",
        with: "probe.core.\(newIdentifier)",
      ),
    )
    let source = try workspace.directory.readFile("src/\(oldIdentifier).ts")
    try workspace.directory.writeFile(
      "src/\(oldIdentifier).ts",
      contents: source.replacingOccurrences(
        of: "probe.core.\(oldIdentifier)",
        with: "probe.core.\(newIdentifier)",
      ),
    )
    return workspace
  }

  // golden_rename. Both halves of the break name the rename, and following the
  // remediation exactly leaves the matrix clean.
  @Test
  func `both halves name the rename, and the remediation actually works`()
    async throws
  {
    let workspace = try await Self.renamedWorkspace(from: "oldname", to: "newname")
    let human = try await SignalsWorkspace.runHuman(workspace, ["scan", "--repo", "."])
      .standardOutput

    #expect(
      human.contains("renamed to probe.core.newname"),
      "the orphaned registration names what it became",
    )
    #expect(
      human.contains("renamed from probe.core.oldname"),
      "the new marker names what it came from",
    )
    // Truthful about the append-only registry: release BEFORE re-registering,
    // because bind fails closed while the stale registration stands.
    #expect(human.contains("use-cases unbind --row probe.core.oldname --reason row_renamed"))
    #expect(human.contains("--register-existing"))

    let released = try await SignalsWorkspace.run(workspace, [
      "unbind", "--repo", ".", "--row", "probe.core.oldname", "--reason", "row_renamed",
    ])
    #expect(
      released.isOk == true,
      Comment(rawValue: "unbind failed: \(released.standardError)"),
    )
    let rebound = try await SignalsWorkspace.run(workspace, [
      "bind", "--repo", ".", "--row", "probe.core.newname",
      "--file", "src/oldname.ts", "--register-existing",
    ])
    #expect(
      rebound.isOk == true,
      Comment(rawValue: "re-register failed: \(rebound.standardError)"),
    )

    let scanned = try await SignalsWorkspace.run(workspace, ["scan", "--repo", "."])
    let integrity = scanned.data.at("status.integrity_errors")?.arrayValue ?? []
    #expect(
      integrity.isEmpty,
      "following the remediation exactly must leave zero integrity errors",
    )
  }

  // edge_errors_reach_the_human_output. An agent reading the default output
  // must not be left thinking the matrix is clean.
  @Test
  func `integrity errors appear in the human output, not only in JSON`()
    async throws
  {
    let workspace = try await Self.renamedWorkspace(from: "oldname", to: "newname")
    let human = try await SignalsWorkspace.runHuman(workspace, ["scan", "--repo", "."])
    #expect(human.standardOutput.contains("integrity errors"))
    #expect(human.standardOutput.contains("REGISTRY_ROW_MISSING"))
    #expect(human.exitCode != 0, "a broken registry must not exit 0")
  }

  // bad_unrelated_marker_is_not_blamed. A genuinely new behaviour must not be
  // reported as a rename of an unrelated orphan — a guess offered as a fact is
  // worse than no guess.
  @Test
  func `an unrelated orphaned registration is not blamed on a rename`()
    async throws
  {
    let workspace = try await Self.renamedWorkspace(
      from: "alpha",
      to: "somethingcompletelydifferent",
    )
    let human = try await SignalsWorkspace.runHuman(workspace, ["scan", "--repo", "."])
      .standardOutput
    #expect(human.contains("REGISTRY_ROW_MISSING"))
    #expect(
      !human.contains("renamed to probe.core.somethingcompletelydifferent"),
      "dissimilar ids must not be asserted as a rename",
    )
  }
}
