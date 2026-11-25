import Testing
@testable import UseCasesTransformers

struct CargoTestLocatorTests {
  @Test
  func `a test the searcher misses in its own file is looked for everywhere`() async {
    let searcher = SpySourceSearching(
      answering: [.missing, .found(file: "src/b.rs", line: 4)],
    )
    var locator = CargoTestLocator(
      searcher: searcher,
      listing: MockSourceListing(listed: ["src/b.rs"]),
      base: "",
    )
    var diagnostics: [String] = []

    let located = locator.locate(
      path: "tests::name",
      outcome: "ok",
      target: "src/lib.rs",
      diagnostics: &diagnostics,
    )

    #expect(
      located == LocatedTest(
        test: "src/lib.rs::tests::name",
        file: "src/b.rs",
        line: 4,
        status: .pass,
      ),
    )
    #expect(diagnostics.isEmpty)
    #expect(
      await searcher.asked() == [
        SpySourceSearching.Search(needles: ["fn name("], files: ["src/lib.rs"]),
        SpySourceSearching.Search(needles: ["fn name("], files: ["src/b.rs", "src/b.rs"]),
      ],
    )
  }

  @Test
  func `a function the searcher finds twice is left unlinked with a note`() {
    var locator = CargoTestLocator(
      searcher: SpySourceSearching(answering: [.ambiguous(count: 2)]),
      listing: MockSourceListing(listed: []),
      base: "",
    )
    var diagnostics: [String] = []

    let located = locator.locate(
      path: "tests::name",
      outcome: "ok",
      target: nil,
      diagnostics: &diagnostics,
    )

    #expect(located.file == nil)
    #expect(located.line == nil)
    #expect(diagnostics == ["test tests::name matches several functions; left unlinked"])
  }
}
