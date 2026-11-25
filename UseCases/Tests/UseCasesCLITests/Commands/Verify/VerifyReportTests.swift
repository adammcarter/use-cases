import Testing
import UseCasesCore
@testable import UseCasesCLI

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
