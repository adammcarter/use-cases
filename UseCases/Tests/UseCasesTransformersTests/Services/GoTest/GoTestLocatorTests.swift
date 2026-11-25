import Testing
@testable import UseCasesTransformers

struct GoTestLocatorTests {
  private let test = GoTestEvents.Test(
    package: "example.com/svc/pkg",
    name: "TestX",
  )

  private func locator(searching searcher: SpySourceSearching) throws -> GoTestLocator {
    try GoTestLocator(
      module: GoModule(
        modFile: "/w/go.mod",
        reader: MockReportReader(texts: ["/w/go.mod": "module example.com/svc\n"]),
      ),
      base: "",
      searcher: searcher,
      listing: MockSourceListing(listed: ["pkg/a_test.go", "pkg/a.go"]),
    )
  }

  @Test
  func `a test is looked for in the test files of its package by the searcher it is given`()
    async throws
  {
    let searcher = SpySourceSearching(answering: [.found(file: "pkg/a_test.go", line: 9)])
    var locator = try locator(searching: searcher)
    var diagnostics: [String] = []

    let located = locator.locate(
      test,
      diagnostics: &diagnostics,
    )

    #expect(located?.file == "pkg/a_test.go")
    #expect(located?.line == 9)
    #expect(diagnostics.isEmpty)
    #expect(
      await searcher.asked() == [
        SpySourceSearching.Search(needles: ["func TestX("], files: ["pkg/a_test.go"]),
      ],
    )
  }

  @Test
  func `a declaration the searcher finds twice is left unlinked with a note`() throws {
    var locator = try locator(searching: SpySourceSearching(answering: [.ambiguous(count: 2)]))
    var diagnostics: [String] = []

    let located = locator.locate(
      test,
      diagnostics: &diagnostics,
    )

    #expect(located == nil)
    #expect(
      diagnostics == ["example.com/svc/pkg.TestX is declared more than once; left unlinked"],
    )
  }
}
