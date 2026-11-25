import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct InitReportTests {
  private let place: InitFolder

  init() throws {
    place = try InitFolder()
  }

  private func plan(
    git: Bool = false,
    ignore: String? = nil,
  ) throws -> InitPlan {
    if git {
      try place.folder.write(".git/HEAD", "x")
    }

    if let ignore {
      try place.folder.write(".gitignore", ignore)
    }

    return try WorkspaceInitializer().plan(
      InitRequest(
        folder: place.url,
        form: .full,
        prefix: nil,
      ),
    )
  }

  @Test
  func `a gitignore that already excludes the store is said to`() throws {
    let report = try InitReport(
      plan: plan(ignore: ".use-cases/\n"),
      hooks: [],
      notes: [],
      isDryRun: false,
    )

    #expect(report.humanText(hint: false).contains("present  .use-cases/ is already in .gitignore"))
  }

  @Test
  func `the notes of the plan and of the run come after the files and before the hint`() throws {
    let report = try InitReport(
      plan: plan(),
      hooks: [],
      notes: ["cancelled too late to stop the write: the files were written"],
      isDryRun: false,
    )

    let lines = report.humanText(hint: true).components(separatedBy: "\n")

    #expect(lines.suffix(3).first?.hasPrefix("note: no version control") == true)
    #expect(lines.suffix(2)
      .first == "note: cancelled too late to stop the write: the files were written")
    #expect(lines.last == "→ use-cases status")
  }

  @Test
  func `a dry run has no hint even when one is wanted`() throws {
    let report = try InitReport(
      plan: plan(git: true),
      hooks: [],
      notes: [],
      isDryRun: true,
    )

    #expect(!report.humanText(hint: true).contains("→"))
  }

  @Test
  func `the document has the workspace folder, the notes and an empty hooks list`() throws {
    let report = try InitReport(
      plan: plan(),
      hooks: [],
      notes: ["late"],
      isDryRun: false,
    )

    let document = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(report.jsonText().utf8),
    )

    #expect(document["workspace"] == .string(place.realPath))
    #expect(document["hooks"] == .array([]))

    guard case let .array(notes)? = document["notes"] else {
      Issue.record("no notes")
      return
    }

    #expect(notes.count == 2)
    #expect(notes.last == .string("late"))
  }

  @Test
  func `a hook added is a line after gitignore saying what it runs`() throws {
    let report = try InitReport(
      plan: plan(git: true),
      hooks: [.commit, .push],
      notes: [],
      isDryRun: false,
    )

    let lines = report.humanText(hint: true).components(separatedBy: "\n")

    #expect(lines.suffix(3).first == "added    the commit hook (use-cases validate)")
    #expect(lines.suffix(2).first == "added    the push hook (use-cases status --gate)")
    #expect(lines.last == "→ use-cases status")
  }

  @Test
  func `a dry run says would of the hooks`() throws {
    let report = try InitReport(
      plan: plan(git: true),
      hooks: [.push],
      notes: [],
      isDryRun: true,
    )

    #expect(
      report.humanText(hint: true).components(separatedBy: "\n").last
        == "would add     the push hook (use-cases status --gate)",
    )
  }

  @Test
  func `the document lists the hooks added by name`() throws {
    let report = try InitReport(
      plan: plan(),
      hooks: [.commit, .push],
      notes: [],
      isDryRun: false,
    )

    let document = try JSONDecoder().decode(
      JSONValue.self,
      from: Data(report.jsonText().utf8),
    )

    #expect(document["hooks"]?.strings == ["commit", "push"])
  }
}
