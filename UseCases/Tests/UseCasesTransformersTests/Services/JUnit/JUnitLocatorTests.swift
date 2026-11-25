import Testing
@testable import UseCasesTransformers

struct JUnitLocatorTests {
  private let testCase = JUnitCase(
    className: "pkg.Foo",
    name: "test_x",
    file: nil,
    line: nil,
    statusAttribute: nil,
    children: [],
  )

  private func locator(searching searcher: SpySourceSearching) throws -> JUnitLocator {
    try JUnitLocator(
      settings: JUnitSettings(
        settings: TransformerSettings(
          values: [
            "find": .string("pattern"),
            "files": .string("src/**"),
            "patterns": .array([.string("def {name}(")]),
          ],
        ),
      ),
      paths: WorkspacePaths(codeRoot: "/w"),
      workingDirectory: "",
      searcher: searcher,
      listing: MockSourceListing(listed: ["src/a.py"]),
    )
  }

  @Test
  func `a test is looked for by the pattern in the files, through the searcher it is given`()
    async throws
  {
    let searcher = SpySourceSearching(answering: [.found(file: "src/a.py", line: 3)])
    var locator = try locator(searching: searcher)
    var diagnostics: [String] = []

    let located = locator.locate(
      testCase,
      diagnostics: &diagnostics,
    )

    #expect(located.file == "src/a.py")
    #expect(located.line == 3)
    #expect(diagnostics.isEmpty)
    #expect(
      await searcher.asked() == [
        SpySourceSearching.Search(needles: ["def test_x("], files: ["src/a.py"]),
      ],
    )
  }

  @Test
  func `a declaration the searcher finds twice is left unlinked with a note`() throws {
    var locator = try locator(searching: SpySourceSearching(answering: [.ambiguous(count: 2)]))
    var diagnostics: [String] = []

    let located = locator.locate(
      testCase,
      diagnostics: &diagnostics,
    )

    #expect(located.file == nil)
    #expect(located.line == nil)
    #expect(
      diagnostics == ["test pkg.Foo.test_x matches 2 declarations; left unlinked"],
    )
  }
}
