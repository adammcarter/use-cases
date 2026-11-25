import Foundation
import Testing
@testable import UseCasesCore

struct BundledGuideLoaderTests {
  let loader = BundledGuideLoader()

  @Test(arguments: BundledGuideLoader.names)
  func `each bundled copy is byte for byte the published guide`(name: String) throws {
    let published = try Data(contentsOf: DocsGuides.folder().appending(path: "\(name).md"))

    #expect(try loader.guideData(named: name) == published)
  }

  @Test
  func `no guide is published that the build does not bundle, and none is bundled unpublished`()
    throws
  {
    let published = try FileManager.default
      .contentsOfDirectory(atPath: DocsGuides.folder().path)
      .filter {
        $0.hasSuffix(".md")
      }
      .map {
        String($0.dropLast(3))
      }
      .sorted()

    #expect(published == BundledGuideLoader.names.sorted())
  }

  @Test
  func `the guides come in the order of the table of the design`() throws {
    let guides = try loader.guides()

    #expect(guides.map(\.name) == [
      "getting-started", "writing-use-cases", "finding", "linking", "verifying", "reading-status",
      "ci-and-hooks", "quirks",
    ])
  }

  @Test
  func `every bundled guide has a title, what it covers, and its text as shipped`() throws {
    for guide in try loader.guides() {
      #expect(!guide.title.isEmpty)
      #expect(!guide.covers.isEmpty)
      #expect(try loader.guideData(named: guide.name) == Data(guide.text.utf8))
      #expect(guide.sections.first?.heading == guide.title)
    }
  }

  @Test
  func `a bundle with no copy of a guide says which is missing`() throws {
    let empty = try #require(Bundle(path: FileManager.default.temporaryDirectory.path))
    let loader = BundledGuideLoader(
      bundle: empty,
      parser: GuideParser(),
    )

    #expect(throws: GuideLoadingError.missing("getting-started")) {
      try loader.guides()
    }
  }

  @Test
  func `a copy that is not UTF-8 text is reported as unreadable`() throws {
    try withBundle(holding: Data([0xFF, 0xFE, 0x23])) { bundle in
      let loader = BundledGuideLoader(
        bundle: bundle,
        parser: GuideParser(),
      )

      #expect(throws: GuideLoadingError.unreadable("getting-started")) {
        try loader.guides()
      }
    }
  }

  @Test
  func `a copy that is not a guide is reported as invalid`() throws {
    try withBundle(holding: Data("no title here\n".utf8)) { bundle in
      let loader = BundledGuideLoader(
        bundle: bundle,
        parser: GuideParser(),
      )

      #expect(throws: GuideLoadingError.invalid("getting-started")) {
        try loader.guides()
      }
    }
  }

  /// Runs `body` with a bundle holding `contents` as the first guide, in the place a build keeps
  /// it, and removes the bundle afterwards.
  private func withBundle(
    holding contents: Data,
    _ body: (Bundle) throws -> Void,
  ) throws {
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer {
      try? FileManager.default.removeItem(at: folder)
    }

    let guides = folder.appending(path: "Guides")
    try FileManager.default.createDirectory(
      at: guides,
      withIntermediateDirectories: true,
    )
    try contents.write(to: guides.appending(path: "getting-started.md"))

    try body(#require(Bundle(path: folder.path)))
  }
}
