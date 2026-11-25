import Testing
@testable import UseCasesCore

struct WorkspaceWarningTests {
  private static let run = "0192f0c4e5a17c3e9b04d2f61a8c3b57"
  private static let shortener = RunIdentifierShortener(runs: [run])

  @Test
  func `a run that never finished is told by its short or its whole id`() {
    let warning = WorkspaceWarning.runNeverFinished(run: Self.run)

    #expect(warning.text(shortening: Self.shortener) == "run 0192f0c4 never finished")
    #expect(
      warning.text(shortening: nil)
        == "run 0192f0c4e5a17c3e9b04d2f61a8c3b57 never finished",
    )
  }

  @Test
  func `a note is told as written`() {
    let warning = WorkspaceWarning.note("src/a.swift: skipped")

    #expect(warning.text(shortening: Self.shortener) == "src/a.swift: skipped")
  }
}
