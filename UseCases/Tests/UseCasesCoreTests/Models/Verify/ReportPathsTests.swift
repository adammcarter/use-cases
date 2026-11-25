import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct ReportPathsTests {
  private func paths(_ lines: [String]) throws -> ReportPaths {
    let fixture = try VerifyFixture(bridge: BridgeFileSamples.validation(lines: lines))
    let validation = try #require(fixture.resolved().workspace.bridge?.validations.first)

    return ReportPaths(validation: validation)
  }

  @Test
  func `a named report is a file inside the validation's folder`() throws {
    let report = try paths(["report: unit.xml"])

    #expect(report.relative == "reports/unit-tests/unit.xml")
    #expect(report.folder == "reports/unit-tests")
  }

  @Test
  func `without a name the report is the folder`() throws {
    let report = try paths([])

    #expect(report.relative == "reports/unit-tests")
  }

  @Test
  func `the absolute path is in the run of the workspace`() throws {
    let report = try paths(["report: unit.xml"])
    let run = RunIdentifier.sample(3)

    #expect(
      report.absolute(of: run, in: URL(fileURLWithPath: "/work/shop"))
        == "/work/shop/.use-cases/runs/\(run.text)/reports/unit-tests/unit.xml",
    )
  }
}
