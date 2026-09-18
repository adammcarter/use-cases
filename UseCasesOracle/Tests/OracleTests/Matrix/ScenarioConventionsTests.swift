import Foundation
import Testing

/// The scenario naming convention, enforced.
///
/// `docs/rewrite/scenario-conventions.md` §1 says a scenario's id carries its
/// role — `<row-id>.golden|bad|edge|stress[_<qualifier>]` — precisely so that
/// "every active row has a bad path" is a check rather than an assertion. Until
/// now the only thing that ever checked it was
/// `scripts/check-scenario-conventions.mjs`, which nothing ran: not CI, not a
/// hook, not the gate. A rule nothing checks is decoration, so the script was
/// ported here and deleted.
///
/// The mechanics live in ``ScenarioConventions``; this file is what fails.
struct ScenarioConventionsTests {
  static let repositoryRoot = OracleLayout.repositoryRoot

  static func report(_ findings: [ScenarioConventions.Finding]) -> String {
    findings.map(\.text).joined(separator: "\n")
  }

  @Test
  func `every active row not exempted by the conventions document follows the naming rule`()
    throws
  {
    let findings = try ScenarioConventions.scenarioFindings(repositoryRoot: Self.repositoryRoot)
    let unexpected = findings.filter { finding in
      ScenarioConventions.doctrineRows[finding.rowIdentifier] == nil
    }

    #expect(
      unexpected.isEmpty,
      Comment(rawValue: """
      A row broke the scenario convention in docs/rewrite/scenario-conventions.md §1.
      Give it golden/bad/edge/stress scenario ids, or tag it no-bad-path / no-edge-path
      with the reason. Do not add it to ScenarioConventions.doctrineRows unless the
      owner has agreed it is doctrine no command can implement.
      \(Self.report(unexpected))
      """),
    )
  }

  @Test
  func `the documented exemptions are still earned, and are still exactly eight`() throws {
    let findings = try ScenarioConventions.scenarioFindings(repositoryRoot: Self.repositoryRoot)
    let failing = Set(findings.map(\.rowIdentifier))
    let exempted = Set(ScenarioConventions.doctrineRows.keys)

    // An exemption that no longer applies is a lie in the other direction: the
    // row was fixed, or retired, and the list should shrink.
    let unearned = exempted.subtracting(failing).sorted()
    #expect(
      unearned.isEmpty,
      Comment(rawValue: "these rows no longer need their §8a exemption — "
        + "remove them from ScenarioConventions.doctrineRows: \(unearned.joined(separator: ", "))"),
    )
    #expect(exempted.count == 8, "scenario-conventions.md §8a names eight doctrine rows")
    // Every exemption says why, so settling §8a is a reading exercise.
    for (row, reason) in ScenarioConventions.doctrineRows {
      #expect(!reason.isEmpty, Comment(rawValue: "\(row) is exempted without a reason"))
    }
  }

  @Test
  func `every active row has something that can run, bar the two written up as open`() throws {
    let findings = try ScenarioConventions.verifierFindings(repositoryRoot: Self.repositoryRoot)
    let unexpected = findings.filter { finding in
      ScenarioConventions.rowsWithNothingRunnable[finding.rowIdentifier] == nil
    }

    #expect(
      unexpected.isEmpty,
      Comment(rawValue: """
      A row has nothing to run: its required_verifiers names an id no verifiers block
      defines, or it declares no verifier at all. This half of the check was ladder row
      2's instrument and it drove the count from 30 to 2; a third row is a regression.
      \(Self.report(unexpected))
      """),
    )

    let failing = Set(findings.map(\.rowIdentifier))
    let cured = Set(ScenarioConventions.rowsWithNothingRunnable.keys)
      .subtracting(failing)
      .sorted()
    #expect(
      cured.isEmpty,
      Comment(rawValue: "these rows now have a verifier — remove them from "
        + "ScenarioConventions.rowsWithNothingRunnable: \(cured.joined(separator: ", "))"),
    )
  }

  @Test
  func `the check reads the whole matrix, so a green run is not an empty one`() throws {
    // The population is not pinned — the conventions document quotes 89 active
    // rows in §6 and 98 in §7, measured days apart — but a reader that found
    // nothing would make every assertion above pass having read no files, which
    // is the silent green the oracle exists to prevent.
    let active = try ScenarioConventions.activeRowCount(repositoryRoot: Self.repositoryRoot)
    #expect(active > 80, "the matrix has far more active rows than this")

    let files = try ScenarioConventions.yamlFiles(
      in: URL(fileURLWithPath: Self.repositoryRoot, isDirectory: true)
        .appendingPathComponent(ScenarioConventions.matrixDirectory, isDirectory: true),
    )
    #expect(files.count > 15, "the matrix is spread across many feature files")
  }
}
