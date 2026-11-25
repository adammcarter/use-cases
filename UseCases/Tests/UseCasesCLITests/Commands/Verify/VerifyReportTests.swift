import Testing
@testable import UseCasesCLI
@testable import UseCasesCore

struct VerifyReportTests {
  private let run = "0192f0c4e5a17c3e9b04d2f61a8c3b57"

  @Test
  func `a started run lines up the reports under the run`() {
    let started = StartedVerifyRun(
      runIdentifier: run,
      selected: ["unit-tests", "ui"],
      reports: [
        StartedReport(validation: "unit-tests", path: "/w/a"),
        StartedReport(validation: "ui", path: "/w/b"),
      ],
      notes: ["first", "other runs are still open: x"],
    )

    #expect(
      VerifyReport.humanText(start: started, hint: true).split(separator: "\n").map(String.init)
        == [
          "started run \(run)",
          "  unit-tests   write the report to /w/a",
          "  ui           write the report to /w/b",
          "other runs are still open: x",
          "→ run your tests, then: use-cases verify --finish --run-id \(run)",
        ],
    )
  }

  @Test
  func `a start that started nothing says why and has no hint`() {
    let started = StartedVerifyRun(
      runIdentifier: nil,
      selected: [],
      reports: [],
      notes: ["nothing to start"],
    )

    #expect(VerifyReport.humanText(start: started, hint: true) == "nothing to start")
  }

  private func finished(unlinked: [UnlinkedTest]) throws -> VerifiedRun {
    try VerifiedRun(
      manifest: RunManifest(
        identifier: RunIdentifier(validating: run),
        createdAt: "2026-01-01T00:00:00Z",
        kind: .verify,
        sources: [],
        errors: ["unit-tests: no report"],
        diagnostics: [],
        unlinkedTests: unlinked,
        notes: ["a note"],
      ),
      results: [],
      isCancelled: false,
    )
  }

  @Test
  func `a finished run lists the tests tied to no use case, worst first, and counts them`() throws {
    let text = try VerifyReport.humanText(
      finish: finished(
        unlinked: [
          UnlinkedTest(test: "S/ok()", file: "Tests/A.swift", line: 7, status: .pass),
          UnlinkedTest(test: "S/broken()", file: "Tests/B.swift", line: 12, status: .fail),
          UnlinkedTest(test: "S/lost()", file: nil, line: nil, status: .error),
        ],
      ),
      hint: true,
    )

    #expect(
      text.split(separator: "\n").map(String.init) == [
        "run 0192f0c4 · 0 verdicts · 1 run error · 3 not tied to a use case",
        "  ! unit-tests: no report",
        "test not tied to a use case",
        "  (no place)  error  S/lost()",
        "  Tests/B.swift:12  fail  S/broken()",
        "  Tests/A.swift:7  pass  S/ok()",
        "a note",
        "→ use-cases status --gate",
      ],
    )
  }

  @Test
  func `a finished run with every test tied says nothing about tests not tied`() throws {
    let text = try VerifyReport.humanText(finish: finished(unlinked: []), hint: false)

    #expect(!text.contains("not tied"))
  }

  @Test
  func `a run id is shortened to its first 8 digits for people`() {
    #expect(VerifyReport.shortened(run) == "0192f0c4")
  }

  @Test
  func `an abort says the run it closed`() {
    #expect(
      VerifyReport.humanText(abort: AbortedVerifyRun(runIdentifier: run)) == "aborted run \(run)",
    )
  }
}
