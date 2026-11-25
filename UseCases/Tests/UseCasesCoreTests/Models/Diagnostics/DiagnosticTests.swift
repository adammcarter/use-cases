import Testing
@testable import UseCasesCore

struct DiagnosticTests {
  private func make(
    file: String = "use-cases/login.yml",
    line: Int? = nil,
    column: Int? = nil,
    code: String = "invalid",
    severity: DiagnosticSeverity = .error,
    message: String = "something is wrong",
  ) throws -> Diagnostic {
    try Diagnostic(
      file: WorkspacePath(validating: file),
      position: line.map {
        try SourcePosition(
          line: $0,
          column: column,
        )
      },
      code: DiagnosticCode(code),
      severity: severity,
      message: message,
    )
  }

  @Test(
    arguments: [
      (("use-cases/login.yml", 12), "use-cases/login.yml:12: bad value"),
      (("use-cases.yml", 1), "use-cases.yml:1: bad value"),
      (("My Tests/a b.yml", 3), "My Tests/a b.yml:3: bad value"),
    ],
  )
  func `a diagnostic with a line renders as file, line and message`(
    place: (file: String, line: Int),
    expected: String,
  ) throws {
    let diagnostic = try make(
      file: place.file,
      line: place.line,
      message: "bad value",
    )

    #expect(diagnostic.description == expected)
  }

  @Test
  func `a diagnostic with no line renders as file and message`() throws {
    let diagnostic = try make(
      file: "use-cases-bridge.yml",
      message: "missing",
    )

    #expect(diagnostic.description == "use-cases-bridge.yml: missing")
  }

  @Test
  func `the column and the severity are not part of the rendering`() throws {
    let error = try make(
      line: 4,
      column: 9,
      severity: .error,
    )
    let warning = try make(
      line: 4,
      column: 9,
      severity: .warning,
    )

    #expect(error.description == "use-cases/login.yml:4: something is wrong")
    #expect(warning.description == error.description)
  }

  @Test
  func `diagnostics sort by file before anything else`() throws {
    let later = try make(
      file: "b.yml",
      line: 1,
      code: "a",
    )
    let earlier = try make(
      file: "a.yml",
      line: 99,
      code: "z",
    )

    #expect([later, earlier].sorted() == [earlier, later])
  }

  @Test
  func `diagnostics in one file sort by line, then by column, before the code`() throws {
    let first = try make(
      line: 2,
      column: 7,
      code: "z",
    )
    let second = try make(
      line: 2,
      column: 8,
      code: "a",
    )
    let third = try make(
      line: 3,
      code: "a",
    )

    #expect([third, second, first].sorted() == [first, second, third])
  }

  @Test
  func `diagnostics at one place sort by code`() throws {
    let first = try make(
      line: 5,
      code: "a-code",
    )
    let second = try make(
      line: 5,
      code: "b-code",
    )

    #expect([second, first].sorted() == [first, second])
  }

  @Test
  func `severity does not change the order`() throws {
    let warning = try make(
      line: 1,
      code: "a",
      severity: .warning,
    )
    let error = try make(
      line: 1,
      code: "b",
      severity: .error,
    )
    let laterWarning = try make(
      line: 2,
      code: "a",
      severity: .warning,
    )
    let earlierError = try make(
      line: 3,
      code: "a",
      severity: .error,
    )

    #expect(
      [earlierError, laterWarning, error, warning].sorted()
        == [warning, error, laterWarning, earlierError],
    )
  }

  @Test
  func `a diagnostic with no position sorts before one with a position in the same file`() throws {
    let fileWide = try make(
      line: nil,
      code: "z",
      message: "file-wide",
    )
    let atLine = try make(
      line: 1,
      code: "a",
      message: "at line 1",
    )
    let otherFile = try make(
      file: "use-cases/z.yml",
      line: nil,
      code: "a",
      message: "other file",
    )

    let ordered = [atLine, otherFile, fileWide].sorted()

    #expect(ordered.map(\.message) == ["file-wide", "at line 1", "other file"])
  }

  @Test
  func `every arrangement of the same diagnostics sorts to one order`() throws {
    let diagnostics = try [
      make(
        file: "b.yml",
        line: 1,
        code: "x",
      ),
      make(
        file: "a.yml",
        code: "x",
      ),
      make(
        file: "a.yml",
        line: 4,
        code: "x",
        message: "second",
      ),
      make(
        file: "a.yml",
        line: 4,
        code: "x",
        message: "first",
      ),
      make(
        file: "a.yml",
        line: 4,
        code: "x",
        severity: .warning,
        message: "first",
      ),
      make(
        file: "a.yml",
        line: 2,
        column: 3,
        code: "y",
      ),
    ]
    let expected = diagnostics.sorted()

    #expect(diagnostics.reversed().sorted() == expected)
    #expect((Array(diagnostics.dropFirst()) + [diagnostics[0]]).sorted() == expected)
    #expect((Array(diagnostics.dropLast(2)) + diagnostics.suffix(2).reversed())
      .sorted() == expected)
  }

  @Test
  func `two diagnostics that agree on everything are equal and hash alike`() throws {
    let first = try make(line: 1)
    let second = try make(line: 1)

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test
  func `a different message makes a different diagnostic`() throws {
    let first = try make(
      line: 1,
      message: "one",
    )
    let second = try make(
      line: 1,
      message: "two",
    )

    #expect(first != second)
  }
}
