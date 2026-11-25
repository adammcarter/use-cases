import Testing
@testable import UseCasesTransformers

struct JUnitTransformerPatternTests {
  private let fileLine: [String: JSONValue] = [
    "find": .string("file-line"),
    "line_base": .integer(0),
  ]
  private static let source = "import x\n\ndef test_a():\n    pass\n"

  @Test
  func `file-name finds the test's name as a string in the file the report names`() throws {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "test/math.test.js",
      2,
      4,
    )

    try workspace.folder.write(
      "test/math.test.js",
      """
      import x
      test('adds numbers', () => {
        assert(1)
      })
      """,
    )
    try workspace.writeReport(
      JUnitXML.suite(JUnitXML.testCase(
        "adds numbers",
        file: workspace.folder.absolute("test/math.test.js"),
        line: nil,
      )),
    )

    let response = try JUnitTransformer().results(
      for: workspace.request(
        links: [link],
        settings: ["find": .string("file-name")],
      ),
    )

    #expect(response.status(of: link) == .pass)
  }

  @Test
  func `file-name leaves a test unlinked when its name appears twice in the file`() throws {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "t.js",
      1,
      9,
    )

    try workspace.folder.write(
      "t.js",
      "test('dup', f)\ntest(\"dup\", g)\n",
    )
    try workspace.writeReport(JUnitXML.suite(JUnitXML.testCase(
      "dup",
      file: "t.js",
      line: nil,
    )))

    let response = try JUnitTransformer().results(
      for: workspace.request(
        links: [link],
        settings: ["find": .string("file-name")],
      ),
    )

    #expect(response.results.isEmpty)
    #expect(response.unlinked.count == 1)
    #expect(response.diagnostics == ["test t.dup matches 2 declarations; left unlinked"])
  }

  private func patternRun(
    classname: String,
    name: String,
    classFile: Bool,
    extraFile: String? = nil,
  ) throws -> (ResultsResponse, RequestLink) {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "src/test/java/LoginTest.java",
      3,
      5,
    )

    try workspace.folder.write(
      "src/test/java/LoginTest.java",
      """
      class LoginTest {
        @Test
        void validLogin() {
          ok();
        }
      }
      """,
    )

    if let extraFile {
      try workspace.folder.write(
        "src/test/java/OtherTest.java",
        extraFile,
      )
    }

    try workspace.writeReport(JUnitXML.suite(JUnitXML.testCase(
      name,
      file: nil,
      line: nil,
      classname: classname,
    )))

    let response = try JUnitTransformer().results(
      for: workspace.request(
        links: [link],
        settings: [
          "find": .string("pattern"),
          "files": .string("src/test/**/*.java"),
          "patterns": .array([.string("void {method}(")]),
          "class_file": .bool(classFile),
        ],
      ),
    )

    return (response, link)
  }

  @Test
  func `pattern finds a declaration by name`() throws {
    let (response, link) = try patternRun(
      classname: "com.shop.LoginTest",
      name: "validLogin",
      classFile: true,
    )

    #expect(response.status(of: link) == .pass)
  }

  @Test
  func `the method is the name before any parenthesis`() throws {
    let (response, link) = try patternRun(
      classname: "com.shop.LoginTest",
      name: "validLogin()",
      classFile: true,
    )

    #expect(response.status(of: link) == .pass)
  }

  @Test
  func `a nested class is found in the file of its outer class`() throws {
    let (response, link) = try patternRun(
      classname: "com.shop.LoginTest$Inner",
      name: "validLogin",
      classFile: true,
    )

    #expect(response.status(of: link) == .pass)
  }

  @Test
  func `the same method in two files is ambiguous unless class_file narrows it`() throws {
    let other = """
    class OtherTest {
      void validLogin() {
      }
    }
    """
    let (wide, _) = try patternRun(
      classname: "com.shop.LoginTest",
      name: "validLogin",
      classFile: false,
      extraFile: other,
    )
    let (narrow, link) = try patternRun(
      classname: "com.shop.LoginTest",
      name: "validLogin",
      classFile: true,
      extraFile: other,
    )

    #expect(wide.results.isEmpty)
    #expect(wide
      .diagnostics == ["test com.shop.LoginTest.validLogin matches 2 declarations; left unlinked"])
    #expect(narrow.status(of: link) == .pass)
  }

  @Test
  func `a test whose declaration cannot be found is unlinked with a note`() throws {
    let (response, link) = try patternRun(
      classname: "com.shop.LoginTest",
      name: "missing",
      classFile: true,
    )

    #expect(response.status(of: link) == nil)
    #expect(response.unlinked.map(\.test) == ["com.shop.LoginTest/missing"])
    #expect(
      response.diagnostics == [
        "test com.shop.LoginTest.missing has no declaration in the source; left unlinked",
      ],
    )
  }

  @Test
  func `a java package named build is searched`() throws {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "src/test/java/com/acme/build/BuildTest.java",
      1,
      9,
    )

    try workspace.folder.write(
      "src/test/java/com/acme/build/BuildTest.java",
      """
      class BuildTest {
        void compiles() {
        }
      }
      """,
    )
    try workspace.writeReport(
      JUnitXML.suite(
        JUnitXML.testCase(
          "compiles",
          file: nil,
          line: nil,
          classname: "com.acme.build.BuildTest",
        ),
      ),
    )

    let response = try JUnitTransformer().results(
      for: workspace.request(
        links: [link],
        settings: [
          "find": .string("pattern"),
          "files": .string("src/test/**/*.java"),
          "patterns": .array([.string("void {method}(")]),
        ],
      ),
    )

    #expect(response.status(of: link) == .pass)
  }
}
