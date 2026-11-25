import Testing
@testable import UseCasesCore

struct WorkspaceWarningTests {
  private static let run = "0192f0c4e5a17c3e9b04d2f61a8c3b57"

  @Test
  func `a run that never finished is told by its short or its whole id`() {
    let warning = WorkspaceWarning.runNeverFinished(run: Self.run)

    #expect(warning.text(shortRunIdentifiers: true) == "run 0192f0c4 never finished")
    #expect(
      warning.text(shortRunIdentifiers: false)
        == "run 0192f0c4e5a17c3e9b04d2f61a8c3b57 never finished",
    )
  }

  @Test
  func `a note is told as written`() {
    let warning = WorkspaceWarning.note("src/a.swift: skipped")

    #expect(warning.text(shortRunIdentifiers: true) == "src/a.swift: skipped")
  }
}
