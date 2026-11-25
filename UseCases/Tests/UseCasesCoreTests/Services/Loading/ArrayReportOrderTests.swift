import Testing
@testable import UseCasesCore

struct ArrayReportOrderTests {
  private func diagnostic(
    _ file: String,
    line: Int? = nil,
    code: DiagnosticCode = "c",
  ) throws -> Diagnostic {
    try Diagnostic(
      file: workspacePath(file),
      position: line.map { line in try SourcePosition(line: line) },
      code: code,
      severity: .error,
      message: "m",
    )
  }

  @Test
  func `diagnostics come back by file, then position, then code, whatever order they were found`()
    throws
  {
    let found = try [
      diagnostic("b.yml", line: 1),
      diagnostic("a.yml", line: 9),
      diagnostic("a.yml", line: 2, code: "z"),
      diagnostic("a.yml", line: 2, code: "b"),
      diagnostic("a.yml"),
    ]

    #expect(
      found.inReportOrder.map(\.description) == [
        "a.yml: m",
        "a.yml:2: m",
        "a.yml:2: m",
        "a.yml:9: m",
        "b.yml:1: m",
      ],
    )
    #expect(found.inReportOrder.map(\.code.text) == ["c", "b", "z", "c", "c"])
  }

  @Test
  func `a diagnostic found twice is reported once`() throws {
    let found = try [
      diagnostic("a.yml", line: 1),
      diagnostic("b.yml"),
      diagnostic("a.yml", line: 1),
    ]

    #expect(found.inReportOrder.count == 2)
  }

  @Test
  func `no diagnostics stay none`() {
    #expect([Diagnostic]().inReportOrder.isEmpty)
  }
}
