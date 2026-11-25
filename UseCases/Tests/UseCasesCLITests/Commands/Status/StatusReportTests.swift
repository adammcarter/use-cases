import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct StatusReportTests {
  private let workspace: StatusWorkspace

  init() throws {
    workspace = try StatusWorkspace()
  }

  private func status() throws -> WorkspaceStatus {
    let loaded = try WorkspaceLoader().load(from: .workspace(workspace.folder.url))

    return try StatusJudge().judge(
      loaded,
      links: LinkResolver().resolveLinks(in: loaded),
    )
  }

  private func report(offersRun: Bool) throws -> StatusReport {
    let status = try status()

    return StatusReport(
      workspace: status,
      shown: status.useCases,
      offersRun: offersRun,
    )
  }

  @Test
  func `where a validation has a run command, the hints point at verify run`() async throws {
    await workspace.record("shop.cart.add", "pass")

    let report = try report(offersRun: true)

    #expect(report.listText(hint: true).hasSuffix("→ use-cases verify --run"))
    #expect(report.oneLineText(hint: true)
      .hasSuffix("→ use-cases verify --run   for a baseline, if you want one"))
  }

  @Test
  func `where none has, they point at verify start`() async throws {
    await workspace.record("shop.cart.add", "pass")

    let report = try report(offersRun: false)

    #expect(report.listText(hint: true).hasSuffix("→ use-cases verify --start"))
    #expect(report.verifyStep == "verify --start")
  }

  @Test
  func `a list with nothing to look at or run has no hint`() async throws {
    await workspace.recordEverythingPassing()
    let status = try status()
    let report = StatusReport(
      workspace: status,
      shown: status.useCases.filter { $0.status == .verified },
      offersRun: false,
    )

    #expect(!report.listText(hint: true).contains("→"))
  }

  @Test
  func `one use case is told by its number with the right noun`() throws {
    let status = try status()
    let report = StatusReport(
      workspace: status,
      shown: Array(status.useCases.prefix(1)),
      offersRun: false,
    )

    #expect(report.listText(hint: false).contains("1 use case · 1 unverified"))
  }
}
