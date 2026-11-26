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

  private func finished(
    unlinked: [UnlinkedTest],
    among runIdentifiers: RunIdentifierShortener = RunIdentifierShortener(runs: []),
  ) throws -> VerifiedRun {
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
      runIdentifiers: runIdentifiers,
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
  func `a finished run caps the passing tests not tied to a use case, not the bad ones`() throws {
    let passing = (1 ... 25).map { (number: Int) in
      UnlinkedTest(test: "S/ok\(number)()", file: "Tests/A.swift", line: number, status: .pass)
    }
    let failing = [
      UnlinkedTest(test: "S/broken()", file: "Tests/B.swift", line: 12, status: .fail),
      UnlinkedTest(test: "S/lost()", file: nil, line: nil, status: .error),
    ]
    let lines = try VerifyReport.humanText(
      finish: finished(unlinked: passing + failing),
      hint: true,
    ).split(separator: "\n").map(String.init)

    #expect(lines[0].hasSuffix("· 27 not tied to a use case"))
    let block = try #require(lines.firstIndex(of: "test not tied to a use case"))
    #expect(lines[block + 1] == "  (no place)  error  S/lost()")
    #expect(lines[block + 2] == "  Tests/B.swift:12  fail  S/broken()")
    let listed = lines[(block + 1)...].prefix { line in
      line.hasPrefix("  ") && !line.hasPrefix("  …")
    }
    #expect(listed.count == 20)
    #expect(lines.contains("  … 7 more not tied to a use case (--json lists every one)"))
    #expect(lines.last == "→ use-cases status --gate")
  }

  @Test
  func `a finished run with over 20 bad tests not tied shows them all and no passing`() throws {
    let failing = (1 ... 23).map { (number: Int) in
      UnlinkedTest(test: "S/bad\(number)()", file: "Tests/B.swift", line: number, status: .fail)
    }
    let passed = UnlinkedTest(test: "S/ok()", file: "Tests/A.swift", line: 1, status: .pass)
    let run = try finished(unlinked: failing + [passed])
    let text = VerifyReport.humanText(finish: run, hint: false)

    #expect(text.components(separatedBy: "  fail  ").count - 1 == 23)
    #expect(!text.contains("S/ok()"))
    #expect(text.contains("  … 1 more not tied to a use case (--json lists every one)"))
  }

  @Test
  func `a finished run with every test tied says nothing about tests not tied`() throws {
    let text = try VerifyReport.humanText(finish: finished(unlinked: []), hint: false)

    #expect(!text.contains("not tied"))
  }

  @Test
  func `a finished run is told by the short id the store shortener gives it`() throws {
    let close = "0192f0c4e5b27c3e9b04d2f61a8c3b58"
    let run = try finished(
      unlinked: [],
      among: RunIdentifierShortener(runs: [run, close]),
    )

    #expect(VerifyReport.humanText(finish: run, hint: false).hasPrefix("run 0192f0c4e5a · "))
  }

  @Test
  func `a finished run alone in the store is told by its first 8 digits`() throws {
    let run = try finished(unlinked: [], among: RunIdentifierShortener(runs: [run]))

    #expect(VerifyReport.humanText(finish: run, hint: false).hasPrefix("run 0192f0c4 · "))
  }

  @Test
  func `an abort says the run it closed`() {
    #expect(
      VerifyReport.humanText(abort: AbortedVerifyRun(runIdentifier: run)) == "aborted run \(run)",
    )
  }
}
