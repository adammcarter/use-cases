import Testing
@testable import UseCasesTransformers

struct SwiftTestingEventsTests {
  private typealias Stream = SwiftTestingStream

  private func events(_ text: String) throws -> SwiftTestingEvents {
    try SwiftTestingEvents(
      text: text,
      path: "events.jsonl",
    )
  }

  private func outcome(_ lines: String...) throws -> ResultStatus? {
    let text = ([Stream.test(
      "M.t()",
      file: "/c/a.swift",
      line: 3,
    )] + lines)
      .joined(separator: "\n")

    return try events(text).outcomes["M.t()"]
  }

  @Test
  func `a test that ended with no issue passes`() throws {
    #expect(try outcome(Stream.ended("M.t()")) == .pass)
  }

  @Test
  func `an issue that is not known fails the test, whatever else is said`() throws {
    #expect(try outcome(
      Stream.issue(
        "M.t()",
        isKnown: false,
      ),
      Stream.ended("M.t()"),
    ) == .fail)
    #expect(try outcome(
      Stream.issue(
        "M.t()",
        isKnown: false,
      ),
      Stream.issue(
        "M.t()",
        isKnown: true,
      ),
    ) == .fail)
    #expect(try outcome(
      Stream.issue(
        "M.t()",
        isKnown: true,
      ),
      Stream.issue(
        "M.t()",
        isKnown: false,
      ),
    ) == .fail)
  }

  @Test
  func `a known issue is an expected failure, which is not a pass`() throws {
    #expect(try outcome(
      Stream.issue(
        "M.t()",
        isKnown: true,
      ),
      Stream.ended("M.t()"),
    ) == .incomplete)
  }

  @Test
  func `a skipped test is incomplete even when its end is reported`() throws {
    #expect(try outcome(Stream.skipped("M.t()")) == .incomplete)
    #expect(try outcome(
      Stream.skipped("M.t()"),
      Stream.ended("M.t()"),
    ) == .incomplete)
  }

  @Test
  func `a test that never ended has no outcome`() throws {
    #expect(try outcome() == nil)
  }

  @Test
  func `issues outside any test are counted, not given to a test`() throws {
    let events = try events(Stream.stream(
      Stream.issue(
        nil,
        isKnown: false,
      ),
      Stream.issue(
        nil,
        isKnown: true,
      ),
    ))

    #expect(events.issuesOutsideTests == 2)
    #expect(events.outcomes.isEmpty)
  }

  @Test
  func `only declared test functions are tests`() throws {
    let events = try events(
      Stream.stream(
        Stream.test(
          "M.Suite",
          file: "/c/a.swift",
          line: 1,
          kind: "suite",
        ),
        Stream.test(
          "M.t()",
          file: "/c/a.swift",
          line: 3,
        ),
        Stream.ended("M.Suite"),
        Stream.ended("M.t()"),
      ),
    )

    #expect(events.located(paths: WorkspacePaths(codeRoot: "/c")).map(\.test) == ["M.t()"])
  }

  @Test
  func `a test is placed by the file and line it is declared at`() throws {
    let events = try events(
      Stream.stream(
        Stream.test(
          "M.t()",
          file: "/c/Tests/a.swift",
          line: 7,
        ),
        Stream.ended("M.t()"),
      ),
    )

    #expect(
      events.located(paths: WorkspacePaths(codeRoot: "/c"))
        == [LocatedTest(
          test: "M.t()",
          file: "Tests/a.swift",
          line: 7,
          status: .pass,
        )],
    )
  }

  @Test
  func `a test declared outside the workspace has no workspace file`() throws {
    let events = try events(
      Stream.stream(
        Stream.test(
          "M.t()",
          file: "/other/a.swift",
          line: 7,
        ),
        Stream.ended("M.t()"),
      ),
    )

    #expect(events.located(paths: WorkspacePaths(codeRoot: "/c")).first?.file == nil)
  }

  @Test
  func `blank lines and unknown record kinds are ignored`() throws {
    let events = try events("\n{\"kind\": \"metadata\", \"payload\": {}}\n   \n{\"other\": 1}\n")

    #expect(events.outcomes.isEmpty)
    #expect(events.declarations.isEmpty)
  }

  @Test(arguments: ["not json\n", "{\"kind\": \"test\"\n", "[1,\n"])
  func `a line that is not JSON means a damaged stream, which is refused`(text: String) {
    #expect(throws: TransformerFailure.reportMalformed(
      path: "events.jsonl",
      reason: "line 1 is not JSON",
    )) {
      try events(text)
    }
  }

  @Test
  func `the damaged line is named`() {
    #expect(throws: TransformerFailure.reportMalformed(
      path: "events.jsonl",
      reason: "line 3 is not JSON",
    )) {
      try events("{}\n\n{broken\n")
    }
  }

  @Test(arguments: ["\u{2028}", "\u{2029}", "\u{85}", "\r"])
  func `a line separator inside a JSON string does not make the stream malformed`(
    separator: String,
  ) throws {
    let identifier = "M.t\(separator)x()"
    let events = try events(
      Stream.stream(
        Stream.test(
          identifier,
          file: "/c/a.swift",
          line: 3,
        ),
        Stream.ended(identifier),
      ),
    )

    #expect(events.outcomes == [identifier: .pass])
    #expect(events.declarations[identifier]?.line == 3)
  }
}
