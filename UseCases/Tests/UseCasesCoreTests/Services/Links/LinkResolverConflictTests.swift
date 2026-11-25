import Testing
@testable import UseCasesCore

struct LinkResolverConflictTests {
  private let fixture: WorkspaceFixture
  private let code = "one\ntwo\nthree\nfour\nfive\n"

  init() throws {
    fixture = try WorkspaceFixture()
  }

  @Test
  func `a binding in YAML that a marker also names is claimed twice and INVALID`() throws {
    try fixture.writeUseCase(
      routeBindings: [LinkSamples.binding("success", file: "src/app.swift")],
    )
    try fixture.write("src/app.swift", "x\n")
    try fixture.write(
      "tests/app_tests.swift",
      LinkSamples.marked("app.toggle#manual.success", "check()"),
    )

    let resolution = try fixture.resolved()

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "claimed by").count == 1)
    #expect(resolution.problems.first?.hasPrefix("use-cases/toggle.yml: ") == true)
  }

  @Test
  func `the same binding twice on one line shares a link key and is INVALID`() throws {
    try fixture.writeUseCase()
    let id = "app.toggle#manual.x"
    try fixture.write(
      "src/twice.js",
      "/* @use-case:\(id) */ a /* @use-case:end \(id) */ "
        + "/* @use-case:\(id) */ b /* @use-case:end \(id) */\n",
    )

    let resolution = try fixture.resolved()

    #expect(resolution.isInvalid)
    #expect(resolution.problems(containing: "share the link key").count == 1)
    #expect(resolution.problems.first?.hasPrefix("src/twice.js:1: ") == true)
  }

  @Test
  func `the same binding twice on different lines is fine`() throws {
    try fixture.writeUseCase()
    let region = LinkSamples.marked("app.toggle#manual.x", "a")
    try fixture.write("src/twice.js", region + region)

    let resolution = try fixture.resolved()

    #expect(!resolution.isInvalid)
    #expect(resolution.links.count == 2)
  }

  @Test
  func `a binding claimed in one use case does not touch the same id in another`() throws {
    try fixture.writeUseCase(bindings: [LinkSamples.binding("code", file: "src/code.py")])
    try fixture.write("src/code.py", code)
    try fixture.write(
      "use-cases/other.yml",
      LinkSamples.definitions(prefix: "other"),
    )
    try fixture.write(
      "tests/t.py",
      LinkSamples.marked("app.other.toggle#code", "x"),
    )

    #expect(try !fixture.resolved().isInvalid)
  }

  struct Overlap: Sendable {
    let first: String
    let second: String
    let warnings: Int
  }

  @Test(
    arguments: [
      Overlap(first: linesBinding("a", 1, 3), second: linesBinding("b", 3, 4), warnings: 1),
      Overlap(first: linesBinding("a", 1, 2), second: linesBinding("b", 3, 4), warnings: 0),
      Overlap(first: linesBinding("a", 1, 3), second: linesBinding("b", 2, 4), warnings: 1),
    ],
  )
  func `implementation links of one use case that share lines warn once`(
    example: Overlap,
  ) throws {
    try fixture.writeUseCase(bindings: [example.first, example.second])
    try fixture.write("src/code.py", code)

    let resolution = try fixture.resolved()

    #expect(!resolution.isInvalid)
    #expect(resolution.warnings(containing: "overlap").count == example.warnings)
  }

  @Test
  func `links of one route that share lines warn`() throws {
    try fixture.writeUseCase(routeBindings: [linesBinding("a", 1, 3), linesBinding("b", 2, 4)])
    try fixture.write("src/code.py", code)

    #expect(try fixture.resolved().warnings(containing: "overlap").count == 1)
  }

  @Test
  func `an implementation link and a validation link over the same lines say nothing`() throws {
    try fixture.writeUseCase(
      bindings: [linesBinding("a", 1, 3)],
      routeBindings: [linesBinding("b", 2, 4)],
    )
    try fixture.write("src/code.py", code)

    #expect(try fixture.resolved().warningLines.isEmpty)
  }

  @Test
  func `links of two use cases over the same lines say nothing`() throws {
    try fixture.writeUseCase(bindings: [linesBinding("a", 1, 3)])
    try fixture.write(
      "use-cases/other.yml",
      LinkSamples.definitions(bindings: [linesBinding("b", 2, 4)], prefix: "other"),
    )
    try fixture.write("src/code.py", code)

    #expect(try fixture.resolved().warningLines.isEmpty)
  }

  @Test
  func `a marker nested in another of the same use case and route overlaps it`() throws {
    try fixture.writeUseCase()
    let inner = LinkSamples.marked("app.toggle#manual.inner", "def")
    try fixture.write(
      "tests/t.swift",
      LinkSamples.marked("app.toggle#manual.outer", "abc\n" + inner),
    )

    let resolution = try fixture.resolved()

    #expect(resolution.links.count == 2)
    #expect(resolution.warnings(containing: "overlap").count == 1)
    #expect(!resolution.isInvalid)
  }

  @Test
  func `an empty range overlaps nothing`() throws {
    try fixture.write("src/code.py", code)
    try fixture.writeUseCase(
      bindings: [
        linesBinding("a", 1, 3),
        LinkSamples.binding(
          "empty",
          file: "src/code.py",
          start: (2, 3),
          end: (2, 2),
        ),
      ],
    )

    let resolution = try fixture.resolved()

    #expect(resolution.warnings(containing: "overlap").isEmpty)
    #expect(resolution.warnings(containing: "empty range").count == 1)
  }

  @Test
  func `overlap warns and never blocks`() throws {
    try fixture.writeUseCase(bindings: [linesBinding("a", 1, 3), linesBinding("b", 2, 4)])
    try fixture.write("src/code.py", code)

    let resolution = try fixture.resolved()

    #expect(!resolution.isInvalid)
    #expect(resolution.links.count == 2)
  }
}

/// A manual binding of lines of `src/code.py`.
private func linesBinding(
  _ identifier: String,
  _ first: Int,
  _ last: Int,
) -> String {
  LinkSamples.binding(
    identifier,
    file: "src/code.py",
    start: (first, nil),
    end: (last, nil),
  )
}
