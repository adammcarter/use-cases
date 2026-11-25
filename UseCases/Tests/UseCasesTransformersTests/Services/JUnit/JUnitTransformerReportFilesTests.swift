import Testing
@testable import UseCasesTransformers

struct JUnitTransformerReportFilesTests {
  private let fileLine: [String: JSONValue] = [
    "find": .string("file-line"),
    "line_base": .integer(0),
  ]
  private static let source = "import x\n\ndef test_a():\n    pass\n"

  @Test
  func `a folder of reports is read file by file`() throws {
    let workspace = try ResultsWorkspace()
    let first = RequestLink.validation(
      "tests/test_a.py",
      3,
      4,
    )
    let second = RequestLink.validation(
      "tests/test_b.py",
      1,
      9,
      binding: "second",
    )

    try workspace.folder.write(
      "tests/test_a.py",
      JUnitTransformerReportFilesTests.source,
    )
    try workspace.writeReportFile(
      "TEST-a.xml",
      JUnitXML.suite(JUnitXML.testCase()),
    )
    try workspace.writeReportFile(
      "nested/TEST-b.xml",
      JUnitXML.suite(JUnitXML.testCase(
        "test_b",
        file: "tests/test_b.py",
        line: "1",
        inside: "<failure/>",
      )),
    )
    try workspace.writeReportFile(
      "notes.txt",
      "ignored",
    )

    let response = try JUnitTransformer().results(
      for: workspace.request(
        links: [first, second],
        settings: fileLine,
      ),
    )

    #expect(response.status(of: first) == .pass)
    #expect(response.status(of: second) == .fail)
  }

  @Test
  func `no report and an empty report folder both say so, with no results`() throws {
    let missing = try ResultsWorkspace()
    let empty = try ResultsWorkspace()

    try empty.folder.write(
      ResultsWorkspace.reportName + "/.keep",
      "",
    )

    for workspace in [missing, empty] {
      let response = try JUnitTransformer().results(
        for: workspace.request(
          links: [.validation(
            "tests/test_a.py",
            3,
            4,
          )],
          settings: fileLine,
        ),
      )

      #expect(response.results.isEmpty)
      #expect(response.diagnostics == ["no JUnit XML found in the report"])
    }
  }

  @Test
  func `a broken report file is a failure that names the file`() throws {
    let workspace = try ResultsWorkspace()

    try workspace.writeReport("<testsuite><testcase>")

    #expect(throws: TransformerFailure.self) {
      try JUnitTransformer().results(
        for: workspace.request(
          links: [],
          settings: fileLine,
        ),
      )
    }
  }

  @Test
  func `repeated notes are given once, in order`() throws {
    let workspace = try ResultsWorkspace()

    try workspace.folder.write(
      "t.js",
      "test('dup', f)\ntest('dup', g)\n",
    )
    try workspace.writeReport(
      JUnitXML.suite(
        JUnitXML.testCase(
          "dup",
          file: "t.js",
          line: nil,
          classname: "b",
        ),
        JUnitXML.testCase(
          "dup",
          file: "t.js",
          line: nil,
          classname: "a",
        ),
        JUnitXML.testCase(
          "dup",
          file: "t.js",
          line: nil,
          classname: "b",
        ),
      ),
    )

    let response = try JUnitTransformer().results(
      for: workspace.request(
        links: [],
        settings: ["find": .string("file-name")],
      ),
    )

    #expect(
      response.diagnostics == [
        "test a.dup matches 2 declarations; left unlinked",
        "test b.dup matches 2 declarations; left unlinked",
      ],
    )
  }
}
