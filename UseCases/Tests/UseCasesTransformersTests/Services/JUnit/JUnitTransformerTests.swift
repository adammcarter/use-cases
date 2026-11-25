import Testing
@testable import UseCasesTransformers

struct JUnitTransformerTests {
  private static let source = "import x\n\ndef test_a():\n    pass\n"
  private let fileLine: [String: JSONValue] = [
    "find": .string("file-line"),
    "line_base": .integer(0),
  ]

  private func respond(
    to xml: String,
    settings: [String: JSONValue]? = nil,
    workingDirectory: String = ".",
  ) throws -> (ResultsResponse, RequestLink) {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "tests/test_a.py",
      3,
      4,
    )

    try workspace.folder.write(
      "tests/test_a.py",
      JUnitTransformerTests.source,
    )
    try workspace.writeReport(xml)

    let response = try JUnitTransformer().results(
      for: workspace.request(
        links: [link],
        settings: settings ?? fileLine,
        workingDirectory: workingDirectory,
      ),
    )

    return (response, link)
  }

  @Test(arguments: [
    ("", ResultStatus.pass),
    ("<failure/>", .fail),
    ("<error/>", .error),
    ("<skipped/>", .incomplete),
    (#"<skipped type="pytest.xfail" message="xfail"/>"#, .incomplete),
    (#"<flakyFailure message="x"/>"#, .pass),
  ])
  func `the outcome of the test case decides the result`(
    inside: String,
    expected: ResultStatus,
  ) throws {
    let (response, link) = try respond(to: JUnitXML.suite(JUnitXML.testCase(inside: inside)))

    #expect(response.status(of: link) == expected)
    #expect(response.results.first?.tests == ["t/test_a"])
  }

  @Test(arguments: [
    ("<failure/>", "", ResultStatus.pass),
    ("", "<failure/>", .fail),
    ("<error/>", "", .pass),
    ("", "<skipped/>", .incomplete),
  ])
  func `a test written again is a retry and its final attempt decides`(
    first: String,
    second: String,
    expected: ResultStatus,
  ) throws {
    let (response, link) = try respond(
      to: JUnitXML.suite(
        JUnitXML.testCase(inside: first),
        JUnitXML.testCase(inside: second),
      ),
    )

    #expect(response.status(of: link) == expected)
  }

  @Test
  func `parametrised tests at one place combine into the worst`() throws {
    let (response, link) = try respond(
      to: JUnitXML.suite(
        JUnitXML.testCase("test_a[1]"),
        JUnitXML.testCase(
          "test_a[2]",
          inside: "<failure/>",
        ),
        JUnitXML.testCase(
          "test_a[3]",
          inside: "<skipped/>",
        ),
      ),
    )

    #expect(response.status(of: link) == .fail)
    #expect(response.results.first?.tests == ["t/test_a[1]", "t/test_a[2]", "t/test_a[3]"])
  }

  @Test(arguments: [(0, 2), (1, 3)])
  func `lines count from the base the settings say`(
    base: Int,
    reportedLine: Int,
  ) throws {
    let settings: [String: JSONValue] = ["find": .string("file-line"), "line_base": .integer(base)]
    let (response, link) = try respond(
      to: JUnitXML.suite(JUnitXML.testCase(line: "\(reportedLine)")),
      settings: settings,
    )

    #expect(response.status(of: link) == .pass)
  }

  @Test
  func `a test outside every link is unlinked with its place`() throws {
    let (response, link) = try respond(to: JUnitXML.suite(JUnitXML.testCase(line: "20")))

    #expect(response.status(of: link) == nil)
    #expect(
      response.unlinked == [
        UnlinkedTest(
          test: "t/test_a",
          file: "tests/test_a.py",
          line: 21,
          status: .pass,
        ),
      ],
    )
  }

  @Test
  func `a test with no file or line, or a file outside the workspace, is unlinked`() throws {
    let (response, link) = try respond(
      to: JUnitXML.suite(
        JUnitXML.testCase(
          "no_file",
          file: nil,
        ),
        JUnitXML.testCase(
          "no_line",
          line: nil,
        ),
        JUnitXML.testCase(
          "outside",
          file: "/elsewhere/test_a.py",
        ),
      ),
    )

    #expect(response.status(of: link) == nil)
    #expect(response.unlinked.map(\.test) == ["t/no_file", "t/no_line", "t/outside"])
    #expect(response.unlinked.allSatisfy { $0.file == nil && $0.line == nil })
    #expect(response.diagnostics.count == 3)
  }

  @Test
  func `a line that is not a number is unlinked with a note`() throws {
    let (response, _) = try respond(to: JUnitXML.suite(JUnitXML.testCase(line: "two")))

    #expect(response.unlinked.count == 1)
    #expect(response.diagnostics.contains { note in note.contains("line 'two'") })
  }

  @Test
  func `absolute paths in the report are read as they are`() throws {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "tests/test_a.py",
      3,
      4,
    )

    try workspace.folder.write(
      "tests/test_a.py",
      JUnitTransformerTests.source,
    )
    try workspace.writeReport(
      JUnitXML.suite(JUnitXML.testCase(file: workspace.folder.absolute("tests/test_a.py"))),
    )

    let response = try JUnitTransformer().results(
      for: workspace.request(
        links: [link],
        settings: fileLine,
      ),
    )

    #expect(response.status(of: link) == .pass)
  }

  @Test
  func `relative paths start at the working folder, or at base`() throws {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "pricing/tests/test_a.py",
      3,
      4,
    )

    try workspace.folder.write(
      "pricing/tests/test_a.py",
      JUnitTransformerTests.source,
    )
    try workspace.writeReport(JUnitXML.suite(JUnitXML.testCase()))

    let fromWorkingFolder = try JUnitTransformer().results(
      for: workspace.request(
        links: [link],
        settings: fileLine,
        workingDirectory: "pricing",
      ),
    )
    let fromBase = try JUnitTransformer().results(
      for: workspace.request(
        links: [link],
        settings: fileLine.merging(["base": .string("pricing")]) { _, new in new },
      ),
    )

    #expect(fromWorkingFolder.status(of: link) == .pass)
    #expect(fromBase.status(of: link) == .pass)
  }
}
