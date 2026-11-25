import Testing
@testable import UseCasesTransformers

struct JUnitTransformerLineTests {
  private let source = "import x\n\ndef test_a():\n    pass\n"

  private func respond(
    to xml: String,
    lineBase: Int = 0,
  ) throws -> (ResultsResponse, RequestLink) {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "tests/test_a.py",
      3,
      4,
    )

    try workspace.folder.write(
      "tests/test_a.py",
      source,
    )
    try workspace.writeReport(xml)

    let response = try JUnitTransformer().results(
      for: workspace.request(
        links: [link],
        settings: ["find": .string("file-line"), "line_base": .integer(lineBase)],
      ),
    )

    return (response, link)
  }

  @Test(arguments: ["-1", "-5", "-9223372036854775808"])
  func `a line before the first is unlinked with a note, never written out`(line: String) throws {
    let (response, _) = try respond(to: JUnitXML.suite(JUnitXML.testCase(line: line)))

    #expect(response.results.isEmpty)
    #expect(response.unlinked.count == 1)
    #expect(response.unlinked.first?.line == nil)
    #expect(response
      .diagnostics == ["test t.test_a has line '\(line)', which is no line number; left unlinked"])
  }

  @Test
  func `line 0 in a report that counts from 1 is no line`() throws {
    let (response, _) = try respond(
      to: JUnitXML.suite(JUnitXML.testCase(line: "0")),
      lineBase: 1,
    )

    #expect(response.unlinked.first?.line == nil)
    #expect(response.diagnostics.count == 1)
  }

  @Test(arguments: [
    "9223372036854775807",
    "9007199254740991",
    "9007199254740992",
    "99999999999999999999999",
  ])
  func `a line too large for any file is unlinked with a note, never a crash`(
    line: String,
  ) throws {
    let (response, _) = try respond(to: JUnitXML.suite(JUnitXML.testCase(line: line)))

    #expect(response.unlinked.first?.line == nil)
    #expect(response
      .diagnostics == ["test t.test_a has line '\(line)', which is no line number; left unlinked"])
  }

  @Test
  func `the largest line there can be is kept`() throws {
    let (response, _) = try respond(
      to: JUnitXML.suite(JUnitXML.testCase(line: "9007199254740990")),
    )

    #expect(response.unlinked.first?.line == LineRange.largest)
    #expect(response.diagnostics.isEmpty)
  }

  @Test(arguments: [9_223_372_036_854_775_807, -9_223_372_036_854_775_807])
  func `a line base too large to count with is refused`(lineBase: Int) throws {
    #expect(throws: TransformerFailure.settingInvalid(
      name: "line_base",
      expected: "a small whole number",
    )) {
      try respond(
        to: JUnitXML.suite(JUnitXML.testCase()),
        lineBase: lineBase,
      )
    }
  }

  @Test
  func `a test with no file and line says so`() throws {
    let (response, _) = try respond(
      to: JUnitXML.suite(
        JUnitXML.testCase(
          "no_file",
          file: nil,
        ),
        JUnitXML.testCase(
          "no_line",
          line: nil,
        ),
      ),
    )

    #expect(
      response.diagnostics == [
        "test t.no_file has no file and line in the report; left unlinked",
        "test t.no_line has no file and line in the report; left unlinked",
      ],
    )
  }

  @Test
  func `a test in a file outside the workspace says so`() throws {
    let (response, _) = try respond(
      to: JUnitXML.suite(JUnitXML.testCase(file: "/elsewhere/test_a.py")),
    )

    #expect(
      response.diagnostics == [
        "test t.test_a names '/elsewhere/test_a.py', outside the workspace; left unlinked",
      ],
    )
  }
}
