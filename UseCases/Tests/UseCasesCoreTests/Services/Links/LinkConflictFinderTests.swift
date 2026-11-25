import Testing
@testable import UseCasesCore

struct LinkConflictFinderTests {
  private let finder = LinkConflictFinder()

  private func conflicts(_ links: [ResolvedLink]) throws -> [Diagnostic] {
    try finder.conflicts(
      among: links,
      definitions: [
        UseCaseIdentifier(validating: "app.toggle"): WorkspacePath(validating: "use-cases/t.yml"),
      ],
    )
  }

  private func overlaps(_ links: [ResolvedLink]) throws -> [Diagnostic] {
    try conflicts(links).filter { diagnostic in
      diagnostic.code == .overlappingLinks
    }
  }

  struct SpanPair: Sendable {
    let first: Range<Int>
    let second: Range<Int>
    let warnings: Int
  }

  @Test(
    arguments: [
      SpanPair(first: 0 ..< 10, second: 5 ..< 15, warnings: 1),
      SpanPair(first: 0 ..< 10, second: 10 ..< 20, warnings: 0),
      SpanPair(first: 0 ..< 10, second: 11 ..< 20, warnings: 0),
      SpanPair(first: 0 ..< 20, second: 5 ..< 10, warnings: 1),
      SpanPair(first: 0 ..< 10, second: 0 ..< 10, warnings: 1),
      SpanPair(first: 5 ..< 5, second: 0 ..< 10, warnings: 0),
      SpanPair(first: 5 ..< 5, second: 5 ..< 5, warnings: 0),
    ],
  )
  func `two spans overlap when they share a byte`(example: SpanPair) throws {
    let links = try [
      ResolvedLink.sample(binding: "a", span: example.first),
      ResolvedLink.sample(binding: "b", span: example.second),
    ]

    #expect(try overlaps(links).count == example.warnings)
  }

  @Test
  func `three links over the same bytes are three overlapping pairs`() throws {
    let links = try ["a", "b", "c"].map { binding in
      try ResolvedLink.sample(binding: binding, span: 0 ..< 10)
    }

    let found = try overlaps(links)

    #expect(found.count == 3)
    #expect(Set(found.map(\.message)).count == 3)
  }

  @Test
  func `a long span overlaps each short one inside it but they do not overlap each other`() throws {
    let links = try [
      ResolvedLink.sample(binding: "outer", span: 0 ..< 100),
      ResolvedLink.sample(binding: "one", span: 10 ..< 20),
      ResolvedLink.sample(binding: "two", span: 30 ..< 40),
    ]

    #expect(try overlaps(links).count == 2)
  }

  @Test
  func `the warning names both links and sits at the first one's line`() throws {
    let links = try [
      ResolvedLink.sample(binding: "later", lines: 8 ... 9, span: 40 ..< 60),
      ResolvedLink.sample(binding: "earlier", lines: 3 ... 5, span: 20 ..< 50),
    ]

    let warning = try #require(overlaps(links).first)

    #expect(warning.severity == .warning)
    #expect(warning.position?.line == 3)
    #expect(warning.message.contains("app.toggle#earlier@src/a.swift:3"))
    #expect(warning.message.contains("app.toggle#later@src/a.swift:8"))
    #expect(warning.message.contains("overlapping links"))
  }

  @Test
  func `links in different files, routes or use cases never overlap`() throws {
    let links = try [
      ResolvedLink.sample(binding: "a", span: 0 ..< 10),
      ResolvedLink.sample(binding: "b", file: "src/other.swift", span: 0 ..< 10),
      ResolvedLink.sample(route: "unit", binding: "c", span: 0 ..< 10),
      ResolvedLink.sample(route: "ui", binding: "d", span: 0 ..< 10),
      ResolvedLink.sample(useCase: "app.other", binding: "e", span: 0 ..< 10),
    ]

    #expect(try overlaps(links).isEmpty)
  }

  @Test
  func `two links with one key share it`() throws {
    let links = try [
      ResolvedLink.sample(source: .marker, binding: "x", lines: 2 ... 2, span: 0 ..< 5),
      ResolvedLink.sample(source: .marker, binding: "x", lines: 2 ... 2, span: 10 ..< 15),
    ]

    let found = try conflicts(links).filter { $0.code == .linkKeyShared }
    let problem = try #require(found.first)

    #expect(found.count == 1)
    #expect(problem.severity == .error)
    #expect(problem.message.contains("share the link key 'app.toggle#x@src/a.swift:2'"))
    #expect(problem.description.hasPrefix("src/a.swift:2: "))
  }

  @Test
  func `many marker regions of one binding are fine when their keys differ`() throws {
    let links = try [
      ResolvedLink.sample(source: .marker, binding: "x", lines: 2 ... 2, span: 0 ..< 5),
      ResolvedLink.sample(source: .marker, binding: "x", lines: 6 ... 6, span: 10 ..< 15),
      ResolvedLink.sample(source: .marker, binding: "x", file: "src/b.swift", span: 0 ..< 5),
    ]

    #expect(try conflicts(links).isEmpty)
  }

  @Test
  func `a manual binding and a marker under one identity are a binding claimed twice`() throws {
    let links = try [
      ResolvedLink.sample(source: .manual, binding: "x", file: "src/a.swift"),
      ResolvedLink.sample(source: .marker, binding: "x", file: "tests/t.swift", lines: 4 ... 4),
      ResolvedLink.sample(source: .marker, binding: "x", file: "tests/t.swift", lines: 9 ... 9),
    ]

    let found = try conflicts(links).filter { $0.code == .bindingClaimedTwice }
    let problem = try #require(found.first)

    #expect(found.count == 1)
    #expect(problem.severity == .error)
    #expect(problem.file.text == "use-cases/t.yml")
    #expect(problem.message.contains("claimed by a manual binding (src/a.swift)"))
    #expect(problem.message.contains("tests/t.swift:4, tests/t.swift:9"))
  }

  @Test
  func `a marker and a links transformer under one identity are a binding claimed twice`() throws {
    let links = try [
      ResolvedLink.sample(source: .transformer, binding: "x", file: "src/a.swift"),
      ResolvedLink.sample(source: .marker, binding: "x", file: "tests/t.swift", lines: 4 ... 4),
    ]

    let found = try conflicts(links).filter { $0.code == .bindingClaimedTwice }
    let problem = try #require(found.first)

    #expect(found.count == 1)
    #expect(problem.severity == .error)
    #expect(problem.file.text == "use-cases/t.yml")
    #expect(
      problem.message.contains(
        "claimed by markers (tests/t.swift:4) and by a links transformer (src/a.swift:1)",
      ),
    )
  }

  @Test
  func `a manual binding and a links transformer under one identity are claimed twice`() throws {
    let links = try [
      ResolvedLink.sample(source: .manual, binding: "x", file: "src/a.swift"),
      ResolvedLink.sample(source: .transformer, binding: "x", file: "src/b.swift", lines: 3 ... 3),
      ResolvedLink.sample(source: .transformer, binding: "x", file: "src/b.swift", lines: 8 ... 8),
    ]

    let found = try conflicts(links).filter { $0.code == .bindingClaimedTwice }

    #expect(found.count == 1)
    #expect(
      found.first?.message.contains(
        "claimed by a manual binding (src/a.swift) and by a links transformer "
          + "(src/b.swift:3, src/b.swift:8)",
      ) == true,
    )
  }

  @Test
  func `all three sources on one identity are told in one problem`() throws {
    let links = try [
      ResolvedLink.sample(source: .manual, binding: "x", file: "src/a.swift"),
      ResolvedLink.sample(source: .marker, binding: "x", file: "tests/t.swift", lines: 4 ... 4),
      ResolvedLink.sample(source: .transformer, binding: "x", file: "src/b.swift", lines: 2 ... 2),
    ]

    let found = try conflicts(links).filter { $0.code == .bindingClaimedTwice }

    #expect(found.count == 1)
    #expect(found.first?.message.contains("a manual binding") == true)
    #expect(found.first?.message.contains("markers") == true)
    #expect(found.first?.message.contains("a links transformer") == true)
  }

  @Test
  func `many links of one transformer under one identity are fine when their keys differ`() throws {
    let links = try [
      ResolvedLink.sample(source: .transformer, binding: "x", file: "src/a.swift", lines: 2 ... 2),
      ResolvedLink.sample(source: .transformer, binding: "x", file: "src/b.swift", lines: 5 ... 5),
    ]

    #expect(try conflicts(links).isEmpty)
  }

  @Test
  func `a claimed binding is not also reported for sharing a key`() throws {
    let links = try [
      ResolvedLink.sample(source: .manual, binding: "x", file: "src/a.swift", lines: 2 ... 2),
      ResolvedLink.sample(source: .marker, binding: "x", file: "src/a.swift", lines: 2 ... 2),
    ]

    let shared = try conflicts(links).filter { diagnostic in
      diagnostic.code == .linkKeyShared
    }

    #expect(shared.isEmpty)
  }

  @Test
  func `the same binding id in an implementation and in a route is two bindings`() throws {
    let links = try [
      ResolvedLink.sample(source: .manual, binding: "x"),
      ResolvedLink.sample(source: .marker, route: "unit", binding: "x", file: "tests/t.swift"),
    ]

    #expect(try conflicts(links).isEmpty)
  }
}
