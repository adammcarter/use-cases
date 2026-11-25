import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct EditReportTests {
  private let fixture: StatusWorkspace

  init() throws {
    fixture = try StatusWorkspace()
  }

  private func change(_ arguments: [String]) async throws -> UseCaseChange {
    let loaded = try await LinkedWorkspaceLoader(
      loader: WorkspaceLoader(),
      transformers: TransformerLinkResolver(),
      resolver: LinkResolver(),
    ).load(from: .workspace(fixture.folder.url))

    return try UseCaseRemover().plan(
      removing: "shop.pay.wallet",
      in: loaded.workspace,
      links: [],
    )
  }

  @Test
  func `a note that the write was finished after a cancellation is one of the warnings`(
  ) async throws {
    let report = try await EditReport(
      command: "remove",
      change: change([]),
      notes: [CommandResult.tooLate("the files were written")],
      isDryRun: false,
    )

    let document = try JSONDecoder().decode(JSONValue.self, from: Data(report.jsonText().utf8))

    #expect(document["warnings"] ==
      .array([.string("cancelled too late to stop the write: the files were written")]))
    #expect(report.humanText(hint: true)
      .hasSuffix("warning: cancelled too late to stop the write: the files were written"))
  }

  @Test
  func `a remove has no hint`() async throws {
    let report = try await EditReport(
      command: "remove",
      change: change([]),
      notes: [],
      isDryRun: false,
    )

    #expect(!report.humanText(hint: true).contains("→"))
  }
}
