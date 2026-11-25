import Testing
@testable import UseCasesCore

struct StillMarkedWarnerTests {
  private let warner = StillMarkedWarner()

  private func marker(
    _ useCase: String,
    _ file: String,
    _ lines: ClosedRange<Int>,
    source: LinkSource = .marker,
  ) throws -> ResolvedLink {
    try ResolvedLink.sample(
      source: source,
      useCase: useCase,
      file: file,
      lines: lines,
    )
  }

  @Test
  func `a marked region is a line naming its file, its lines and the use case`() throws {
    let lines = try warner.warnings(
      for: ["app.a.x"],
      in: [marker("app.a.x", "tests/a.py", 9 ... 11), marker("app.a.x", "tests/b.py", 4 ... 4)],
    )

    #expect(lines == [
      "tests/a.py:9-11 is still marked for app.a.x",
      "tests/b.py:4 is still marked for app.a.x",
    ])
  }

  @Test
  func `the lines of every use case taken out are sorted together, by file and then place`()
    throws
  {
    let lines = try warner.warnings(
      for: ["app.a.x", "app.a.y"],
      in: [
        marker("app.a.y", "tests/b.py", 5 ... 6),
        marker("app.a.x", "tests/b.py", 30 ... 31),
        marker("app.a.x", "tests/a.py", 50 ... 51),
        marker("app.a.y", "tests/b.py", 2 ... 3),
        marker("app.a.y", "tests/a.py", 50 ... 51),
      ],
    )

    #expect(lines == [
      "tests/a.py:50-51 is still marked for app.a.x",
      "tests/a.py:50-51 is still marked for app.a.y",
      "tests/b.py:2-3 is still marked for app.a.y",
      "tests/b.py:5-6 is still marked for app.a.y",
      "tests/b.py:30-31 is still marked for app.a.x",
    ])
  }

  @Test
  func `a region is listed once however many links it has`() throws {
    let lines = try warner.warnings(
      for: ["app.a.x"],
      in: [marker("app.a.x", "tests/a.py", 9 ... 11), marker("app.a.x", "tests/a.py", 9 ... 11)],
    )

    #expect(lines.count == 1)
  }

  @Test
  func `markers that name other use cases are not listed`() throws {
    let lines = try warner.warnings(
      for: ["app.a.x"],
      in: [marker("app.a.y", "tests/a.py", 9 ... 11), marker("app.a.xx", "tests/a.py", 1 ... 2)],
    )

    #expect(lines.isEmpty)
  }

  @Test(arguments: [LinkSource.manual, .transformer])
  func `only markers are listed, not a manual binding or a transformer's link`(
    source: LinkSource,
  ) throws {
    let lines = try warner.warnings(
      for: ["app.a.x"],
      in: [marker("app.a.x", "tests/a.py", 9 ... 11, source: source)],
    )

    #expect(lines.isEmpty)
  }

  @Test
  func `nothing taken out is nothing to say`() throws {
    #expect(try warner.warnings(for: [], in: [marker("app.a.x", "tests/a.py", 1 ... 1)]).isEmpty)
  }
}
