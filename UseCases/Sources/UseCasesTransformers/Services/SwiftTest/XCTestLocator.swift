/// Finds an XCTest case in the source: `func testName(` in a test file declaring `class Class`,
/// among the files under `Tests/` in the folder the tests ran in.
struct XCTestLocator {
  private var searcher: any SourceSearching
  private let testFiles: [String]

  /// `base` is the folder `swift test` ran in, relative to the code root; "" is the code root.
  init(
    searcher: any SourceSearching,
    listing: any SourceListing,
    base: String,
  ) {
    self.searcher = searcher
    testFiles = listing.files(
      matching: "Tests/**/*.swift",
      under: base,
    )
  }

  mutating func locate(
    _ testCase: XCTestResult,
    diagnostics: inout [String],
  ) -> LocatedTest {
    var file: String?
    var line: Int?

    switch searcher.find(
      needles: ["func \(testCase.name)("],
      in: candidates(for: testCase),
    ) {
    case let .found(foundFile, foundLine):
      file = foundFile
      line = foundLine
    case .ambiguous:
      diagnostics.append(
        "XCTest \(testCase.identifier) is declared more than once; left unlinked",
      )
    case .missing:
      break
    }

    return LocatedTest(
      test: testCase.identifier,
      file: file,
      line: line,
      status: testCase.status,
    )
  }

  /// The test files declaring the class; when the line names a module, those in a folder of that
  /// name (SwiftPM's `Tests/<Module>/`) if there are any.
  private mutating func candidates(for testCase: XCTestResult) -> [String] {
    let declaring = testFiles.filter { file in
      declaresClass(
        testCase.className,
        in: file,
      )
    }

    guard let module = testCase.moduleName else {
      return declaring
    }

    let inModule = declaring.filter { file in
      file.split(separator: "/").dropLast().contains { folder in
        folder == module
      }
    }

    return inModule.isEmpty ? declaring : inModule
  }

  private mutating func declaresClass(
    _ className: String,
    in file: String,
  ) -> Bool {
    guard let lines = searcher.lines(of: file) else {
      return false
    }

    let needle = "class " + className

    return lines.contains { line in
      line.ranges(of: needle).contains { range in
        guard let next = line[range.upperBound...].first else {
          return true
        }

        return !(next.isLetter || next.isNumber || next == "_")
      }
    }
  }
}
