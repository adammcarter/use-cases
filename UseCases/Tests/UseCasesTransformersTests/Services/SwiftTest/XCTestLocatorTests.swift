import Testing
@testable import UseCasesTransformers

struct XCTestLocatorTests {
  @Test
  func `a case is placed through the listing and reader it is given`() {
    let source = """
    final class FooTests {
      func testA() {
      }
    }
    """
    var locator = XCTestLocator(
      searcher: SourceSearcher(
        paths: WorkspacePaths(codeRoot: "/w"),
        reader: MockReportReader(texts: ["/w/Tests/BTests/FooTests.swift": source]),
      ),
      listing: MockSourceListing(listed: ["Tests/BTests/FooTests.swift"]),
      base: "",
    )
    var diagnostics: [String] = []

    let located = locator.locate(
      XCTestResult(
        moduleName: "BTests",
        className: "FooTests",
        name: "testA",
        status: .pass,
      ),
      diagnostics: &diagnostics,
    )

    #expect(
      located == LocatedTest(
        test: "BTests.FooTests.testA",
        file: "Tests/BTests/FooTests.swift",
        line: 2,
        status: .pass,
      ),
    )
    #expect(diagnostics.isEmpty)
  }
}
