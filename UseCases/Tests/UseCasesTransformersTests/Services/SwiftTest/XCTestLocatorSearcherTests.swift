import Testing
@testable import UseCasesTransformers

struct XCTestLocatorSearcherTests {
  @Test
  func `a case is looked for in the files the searcher says declare its class`() async {
    let searcher = SpySourceSearching(
      answering: [.found(file: "Tests/BTests/FooTests.swift", line: 7)],
      sources: [
        "Tests/BTests/FooTests.swift": ["final class FooTests: XCTestCase {"],
        "Tests/BTests/OtherTests.swift": ["final class OtherTests: XCTestCase {"],
      ],
    )
    var locator = XCTestLocator(
      searcher: searcher,
      listing: MockSourceListing(
        listed: ["Tests/BTests/FooTests.swift", "Tests/BTests/OtherTests.swift"],
      ),
      base: "",
    )
    var diagnostics: [String] = []

    let located = locator.locate(
      XCTestResult(
        moduleName: "BTests",
        className: "FooTests",
        name: "testA",
        status: .fail,
      ),
      diagnostics: &diagnostics,
    )

    #expect(
      located == LocatedTest(
        test: "BTests.FooTests.testA",
        file: "Tests/BTests/FooTests.swift",
        line: 7,
        status: .fail,
      ),
    )
    #expect(diagnostics.isEmpty)
    #expect(
      await searcher.asked() == [
        SpySourceSearching.Search(
          needles: ["func testA("],
          files: ["Tests/BTests/FooTests.swift"],
        ),
      ],
    )
  }

  @Test
  func `a function the searcher finds twice is left unlinked with a note`() {
    var locator = XCTestLocator(
      searcher: SpySourceSearching(answering: [.ambiguous(count: 2)]),
      listing: MockSourceListing(listed: []),
      base: "",
    )
    var diagnostics: [String] = []

    let located = locator.locate(
      XCTestResult(
        moduleName: nil,
        className: "FooTests",
        name: "testA",
        status: .pass,
      ),
      diagnostics: &diagnostics,
    )

    #expect(located.file == nil)
    #expect(diagnostics == ["XCTest FooTests.testA is declared more than once; left unlinked"])
  }
}
