import Testing
@testable import UseCasesCore

struct MarkerScannerLanguagesTests {
  /// The comment syntax a language wraps a sentinel in: what comes before and after it.
  private static let syntaxes = [
    CommentSyntax(name: "Swift, C, Java, Kotlin, Go, Rust, JavaScript", before: "// ", after: ""),
    CommentSyntax(name: "Rust doc comment", before: "/// ", after: ""),
    CommentSyntax(name: "Python, Ruby, shell, YAML, Gherkin", before: "# ", after: ""),
    CommentSyntax(name: "SQL, Haskell, Lua, Ada", before: "-- ", after: ""),
    CommentSyntax(name: "C block comment", before: "/* ", after: " */"),
    CommentSyntax(name: "C block comment with no spaces", before: "/*", after: "*/"),
    CommentSyntax(name: "HTML, XML", before: "<!-- ", after: " -->"),
    CommentSyntax(name: "HTML with no spaces", before: "<!--", after: "-->"),
    CommentSyntax(name: "Pascal, OCaml", before: "(* ", after: " *)"),
    CommentSyntax(name: "Batch", before: "REM ", after: ""),
    CommentSyntax(name: "Lisp, assembly", before: ";; ", after: ""),
    CommentSyntax(name: "Visual Basic", before: "' ", after: ""),
    CommentSyntax(name: "Erlang, TeX", before: "% ", after: ""),
    CommentSyntax(name: "Vim script", before: "\" ", after: ""),
    CommentSyntax(name: "Markdown link comment", before: "[//]: # (", after: ")"),
    CommentSyntax(name: "Lua long comment", before: "--[[ ", after: " ]]"),
    CommentSyntax(name: "Haskell block comment", before: "{- ", after: " -}"),
    CommentSyntax(name: "Jupyter cell source", before: "\"# ", after: "\\n\","),
    CommentSyntax(name: "a string literal", before: "let marker = \"", after: "\""),
    CommentSyntax(name: "decoration on both sides", before: "^^^ ", after: " ^^^"),
    CommentSyntax(name: "no syntax at all", before: "", after: ""),
    CommentSyntax(name: "a long banner", before: "################ ", after: " ################"),
    CommentSyntax(name: "Windows paths", before: "C:\\temp> REM ", after: ""),
    CommentSyntax(name: "emoji and CJK", before: "🎉 日本語 ", after: " 🎉"),
  ]

  @Test(arguments: Self.syntaxes)
  func `a pair in any comment syntax is a region`(
    syntax: CommentSyntax,
  ) throws {
    let name = syntax.name
    let before = syntax.before
    let after = syntax.after
    let text =
      "\(before)\(MarkerSamples.open)\(after)\nbody\n\(before)\(MarkerSamples.close)\(after)\n"

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first, "\(name)")
    #expect(scan.regions.count == 1, "\(name)")
    #expect(scan.diagnostics.isEmpty, "\(name)")
    #expect(region.target.text == MarkerSamples.identifier, "\(name)")
    #expect(region.lines == 2 ... 2, "\(name)")
    #expect(MarkerSamples.content(of: region, in: text) == "body\n", "\(name)")
  }

  @Test(arguments: Self.syntaxes)
  func `the same pair on one line is a same-line region in any comment syntax`(
    syntax: CommentSyntax,
  ) throws {
    let name = syntax.name
    let before = syntax.before
    let after = syntax.after
    let text =
      "\(before)\(MarkerSamples.open)\(after) body \(before)\(MarkerSamples.close)\(after)\n"

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first, "\(name)")
    #expect(region.mode == .sameLine, "\(name)")
    #expect(region.lines == 1 ... 1, "\(name)")
    #expect(MarkerSamples.content(of: region, in: text) == "\(after) body \(before)", "\(name)")
  }
}
