import Testing
@testable import UseCasesCore

/// How a file writes a marker comment: resolved per extension, with a shebang
/// fallback for extensionless scripts.
struct CommentPrefixTests {
  @Test(arguments: MarkersGoldenCorpus.commentPrefixCaseNames)
  func `resolves a prefix exactly as the TypeScript does`(caseName: String) throws {
    let entry = try MarkersFixtures.entry(caseName, in: "comment_prefixes")
    let path = try MarkersFixtures.string(entry, "path")

    let prefix = CommentPrefix.resolve(
      filePath: path,
      configuration: MarkersFixtures.configuration(entry),
      contents: MarkersFixtures.optionalString(entry, "contents"),
    )

    #expect(prefix == MarkersFixtures.optionalString(entry, "prefix"))
  }

  @Test
  func `extracts extensions exactly as the TypeScript does`() throws {
    for entry in try MarkersFixtures.section("file_extensions") {
      let path = try MarkersFixtures.string(entry, "path")

      #expect(
        try CommentPrefix.fileExtension(path) == MarkersFixtures.string(entry, "extension"),
        "\(path)",
      )
    }
  }

  /// JavaScript lower-cases a capital sigma at the end of a word to the final
  /// form; a plain per-scalar mapping gives the medial form.
  @Test(arguments: [
    ("f.ΑΣ", ".ας"),
    ("f.Σx", ".σx"),
    ("f.İ", ".i\u{307}"),
  ])
  func `lower-cases an extension the way JavaScript does`(
    path: String,
    expected: String,
  ) {
    #expect(Array(CommentPrefix.fileExtension(path).unicodeScalars) ==
      Array(expected.unicodeScalars))
  }

  @Test
  func `the default map covers the slash and hash languages`() {
    #expect(CommentPrefix.defaults.count == 31)
    #expect(CommentPrefix.defaults[".swift"] == "//")
    #expect(CommentPrefix.defaults[".r"] == "#")
  }
}
