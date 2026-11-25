import Testing
@testable import UseCasesTransformers

struct TestNamesTransformerTests {
  private static let source = """
  import assert from "node:assert/strict";

  test("demo.math.add#unit-tests.adds-numbers", () => {
    assert.equal(add(2, 3), 5);
  });

  test("demo.math.add#core", () => {
    assert.equal(1, 1);
  });

  test("plain test", () => {
    assert.ok(true);
  });
  """

  private let settings: [String: JSONValue] = [
    "files": .string("test/**/*.js"),
    "pattern": .string(#"test\("(?P<id>[^"]+)""#),
  ]

  private func respond(
    source: String = TestNamesTransformerTests.source,
    settings: [String: JSONValue]? = nil,
    useCases: [UseCaseReference] = [
      UseCaseReference(
        id: "demo.math.add",
        routes: [RouteReference(id: "unit-tests")],
      ),
    ],
  ) throws -> LinksResponse {
    let folder = try TemporaryFolder()

    try folder.write(
      "test/math.test.js",
      source,
    )

    return try TestNamesTransformer().links(
      for: LinksRequest(
        useCases: useCases,
        codeRoot: folder.path,
        settings: TransformerSettings(values: settings ?? self.settings),
      ),
    )
  }

  @Test
  func `a name with a route is a validation link and one without is an implementation link`(
  ) throws {
    let response = try respond()

    #expect(
      response.links == [
        ProducedLink(
          useCase: "demo.math.add",
          route: "unit-tests",
          binding: "adds-numbers",
          role: .validation,
          file: "test/math.test.js",
          range: LineRange(
            start: 3,
            end: 3,
          ),
        ),
        ProducedLink(
          useCase: "demo.math.add",
          route: nil,
          binding: "core",
          role: .implementation,
          file: "test/math.test.js",
          range: LineRange(
            start: 7,
            end: 7,
          ),
        ),
      ],
    )
    #expect(response.diagnostics == ["test/math.test.js:11: 'plain test' names no known use case"])
  }

  @Test
  func `block braces reaches the brace that closes the test`() throws {
    var braces = settings

    braces["block"] = .string("braces")

    let response = try respond(settings: braces)

    #expect(response.links.map(\.range) == [
      LineRange(
        start: 3,
        end: 5,
      ),
      LineRange(
        start: 7,
        end: 9,
      ),
    ])
  }

  @Test
  func `a name for an unknown use case or route is a note, not a link`() throws {
    let response = try respond(
      source: """
      test("demo.other#unit-tests.x", f)
      test("demo.math.add#manual.y", f)
      test("not an id", f)
      test("demo.math.add#unit-tests.fine", f)
      """,
    )

    #expect(response.links.map(\.binding) == ["fine"])
    #expect(
      response.diagnostics == [
        "test/math.test.js:1: 'demo.other#unit-tests.x' names no known use case",
        "test/math.test.js:2: 'demo.math.add#manual.y' names no known route",
        "test/math.test.js:3: 'not an id' names no known use case",
      ],
    )
  }

  @Test
  func `several names on one line are each a link`() throws {
    let response = try respond(
      source: "test(\"demo.math.add#core\", f); test(\"demo.math.add#unit-tests.two\", g)\n",
    )

    #expect(response.links.map(\.binding) == ["core", "two"])
  }

  @Test
  func `only files the glob names are searched, in name order`() throws {
    let folder = try TemporaryFolder()

    try folder.write(
      "test/b.js",
      "test(\"demo.math.add#core\", f)\n",
    )
    try folder.write(
      "test/a.js",
      "test(\"demo.math.add#unit-tests.first\", f)\n",
    )
    try folder.write(
      "src/c.js",
      "test(\"demo.math.add#unit-tests.nope\", f)\n",
    )

    let response = try TestNamesTransformer().links(
      for: LinksRequest(
        useCases: [UseCaseReference(
          id: "demo.math.add",
          routes: [RouteReference(id: "unit-tests")],
        )],
        codeRoot: folder.path,
        settings: TransformerSettings(values: settings),
      ),
    )

    #expect(response.links.map(\.file) == ["test/a.js", "test/b.js"])
  }

  @Test
  func `a file that is not UTF-8 text is skipped with a note`() throws {
    let folder = try TemporaryFolder()

    try folder.writeBytes(
      "test/bad.js",
      [0xFF, 0xFE, 0xFD],
    )

    let response = try TestNamesTransformer().links(
      for: LinksRequest(
        useCases: [],
        codeRoot: folder.path,
        settings: TransformerSettings(values: settings),
      ),
    )

    #expect(response.links.isEmpty)
    #expect(response.diagnostics == ["test/bad.js: not UTF-8 text; skipped"])
  }

  @Test
  func `the same request gives the same answer`() throws {
    #expect(try respond() == respond())
  }

  @Test
  func `the files and pattern settings are required`() {
    #expect(throws: TransformerFailure.settingMissing("files")) {
      try respond(settings: ["pattern": .string("(?P<id>x)")])
    }
    #expect(throws: TransformerFailure.settingMissing("pattern")) {
      try respond(settings: ["files": .string("**")])
    }
  }

  @Test
  func `a pattern that is not a regular expression is refused`() {
    #expect(throws: TransformerFailure.settingInvalid(
      name: "pattern",
      expected: "a valid regular expression",
    )) {
      try respond(settings: ["files": .string("**"), "pattern": .string("(unclosed")])
    }
  }

  @Test
  func `a pattern with no id group is refused when it matches`() {
    #expect(throws: TransformerFailure.settingInvalid(
      name: "pattern",
      expected: "a regular expression with a named group `id`",
    )) {
      try respond(settings: ["files": .string("test/**"), "pattern": .string("test")])
    }
  }

  @Test
  func `a block other than line or braces is refused`() {
    var unknownBlock = settings

    unknownBlock["block"] = .string("file")

    let expected = TransformerFailure.settingInvalid(
      name: "block",
      expected: "line or braces",
    )

    #expect(throws: expected) {
      try respond(settings: unknownBlock)
    }
  }
}
