import Foundation
import Testing
@testable import UseCasesCore

struct ProcessRequestReportTests {
  private func request(
    _ arguments: [String],
    reportPath: String?,
  ) -> ProcessRequest {
    ProcessRequest(
      arguments: arguments,
      workingDirectory: URL(fileURLWithPath: "/"),
      reportPath: reportPath,
      timeout: .seconds(1),
    )
  }

  @Test(
    arguments: [
      (["run", "{report}"], ["run", "/runs/r1/reports/unit"]),
      (["--out={report}/unit.xml"], ["--out=/runs/r1/reports/unit/unit.xml"]),
      (["-D", "junitDir={report}"], ["-D", "junitDir=/runs/r1/reports/unit"]),
      (["{report}{report}"], ["/runs/r1/reports/unit/runs/r1/reports/unit"]),
      (["{report}"], ["/runs/r1/reports/unit"]),
      (["{Report}", "{ report }", "{report", "report}", "{{report}}"], [
        "{Report}", "{ report }", "{report", "report}", "{/runs/r1/reports/unit}",
      ]),
      ([], []),
    ] as [([String], [String])],
  )
  func `every exact token in every argument is replaced, and nothing else`(
    arguments: [String],
    expected: [String],
  ) {
    let launched = request(
      arguments,
      reportPath: "/runs/r1/reports/unit",
    ).launchArguments

    #expect(launched == expected)
  }

  @Test
  func `braces around a placeholder are kept and shell variables are left alone`() {
    let shell = "false || { echo {report} ${HOME} ${report}; }"
    let launched = request(
      [shell, "{ }", #"{"k": {report}}"#],
      reportPath: "/runs/r1/reports/unit",
    ).launchArguments

    #expect(launched == [
      "false || { echo /runs/r1/reports/unit ${HOME} ${report}; }",
      "{ }",
      #"{"k": /runs/r1/reports/unit}"#,
    ])
  }

  @Test(arguments: ["/runs/a b/reports", "/runs/it's/reports", "/runs/\"x\"/$HOME/*"])
  func `the path goes in as it is, with no quoting`(path: String) {
    let launched = request(
      ["--out={report}"],
      reportPath: path,
    ).launchArguments

    #expect(launched == ["--out=\(path)"])
  }

  @Test
  func `a path that holds the token is not substituted again`() {
    let launched = request(
      ["{report}"],
      reportPath: "/runs/{report}/x",
    ).launchArguments

    #expect(launched == ["/runs/{report}/x"])
  }

  @Test
  func `without a report path the arguments are launched unchanged`() {
    let launched = request(
      ["tool", "{report}"],
      reportPath: nil,
    ).launchArguments

    #expect(launched == ["tool", "{report}"])
  }

  @Test
  func `the stored command keeps the literal token`() {
    let stored = request(
      ["tool", "{report}"],
      reportPath: "/runs/r1/reports/unit",
    )

    _ = stored.launchArguments

    #expect(stored.arguments == ["tool", "{report}"])
  }
}
