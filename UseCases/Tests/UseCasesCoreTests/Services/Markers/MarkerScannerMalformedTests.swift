import Testing
@testable import UseCasesCore

struct MarkerScannerMalformedTests {
  @Test(
    arguments: [
      ("// @use-case:\n", ""),
      ("// @use-case: example.a#b\n", ""),
      ("// @use-case:Bad_ID\n", ""),
      ("// @use-case:App.login#submit\n", ""),
      ("// @use-case:example.nope\n", "example.nope"),
      ("// @use-case:a#b#c\n", "a#b#c"),
      ("// @use-case:a#b.c.d\n", "a#b.c.d"),
      ("// @use-case:a..b#c\n", "a..b#c"),
      ("// @use-case:.a#b\n", ".a#b"),
      ("// @use-case:a#\n", "a#"),
      ("// @use-case:#b\n", "#b"),
      ("// @use-case:-a#b\n", "-a#b"),
      ("// @use-case:a#-b\n", "a#-b"),
      ("// @use-case:end \n", ""),
      ("// @use-case:end\n", "end"),
      ("// @use-case:end Bad\n", ""),
      ("// @use-case:a.b#submiT\n", "a.b#submi"),
      ("// @use-case:a.b#c_d\n", "a.b#c"),
      ("// @use-case:a.b#c-A\n", "a.b#c"),
      ("// @use-case:end a.b#c_d\n", "a.b#c"),
    ] as [(String, String)],
  )
  func `a malformed id is a warning naming the id, and nothing else`(
    text: String,
    identifier: String,
  ) throws {
    let scan = try MarkerSamples.scan(text)

    let diagnostic = try #require(scan.diagnostics.first)
    #expect(scan.regions.isEmpty)
    #expect(scan.diagnostics.count == 1)
    #expect(diagnostic.severity == .warning)
    #expect(diagnostic.code == .malformedMarkerIdentifier)
    #expect(diagnostic.position?.line == 1)
    #expect(diagnostic.message.hasPrefix("malformed marker id '\(identifier)': "))
    #expect(diagnostic.description.hasPrefix("\(MarkerSamples.file):1: malformed marker id"))
  }

  @Test
  func `an id run followed by a letter, digit or underscore is never read short`() throws {
    let cases = [
      "// @use-case:a.b#submiT\nx\n// @use-case:end a.b#submiT\n",
      "// @use-case:a.b#c_d\nx\n// @use-case:end a.b#c_d\n",
      "// @use-case:a.b#c_d\nx\n// @use-case:end a.b#c\n",
    ]

    for text in cases {
      let scan = try MarkerSamples.scan(text)

      #expect(scan.regions.isEmpty, "in \(text.debugDescription)")
      #expect(
        scan.diagnostics.contains { $0.code == .malformedMarkerIdentifier },
        "in \(text.debugDescription)",
      )
    }
  }

  @Test
  func `a malformed id that would pair if read short is left out of pairing`() throws {
    let text = "// @use-case:a.b#submiT\nx\n// @use-case:end a.b#submi\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.diagnostics.map(\.code) == [.malformedMarkerIdentifier, .markerWithoutStart])
    #expect(scan.regions.isEmpty)
  }

  @Test
  func `a trailing hyphen or dot trimmed off the id is fine when no word follows`() throws {
    let cases = [
      "<!--@use-case:a#b-->\nx\n<!--@use-case:end a#b-->\n",
      "// @use-case:a#b.\nx\n// @use-case:end a#b.\n",
      "// @use-case:a#b- note\nx\n// @use-case:end a#b-\n",
      "/*@use-case:a#b*/\nx\n/*@use-case:end a#b*/\n",
    ]

    for text in cases {
      let scan = try MarkerSamples.scan(text)

      #expect(scan.regions.map(\.target.text) == ["a#b"], "in \(text.debugDescription)")
      #expect(scan.diagnostics.isEmpty, "in \(text.debugDescription)")
    }
  }

  @Test
  func `an empty id says no id follows, and names the text that does`() throws {
    let scan = try MarkerSamples.scan("// @use-case:BAD\n")

    let message = try #require(scan.diagnostics.first?.message)
    #expect(message.hasPrefix("malformed marker id '': no marker id follows the sentinel"))
    #expect(message.contains("'BAD'"))
  }

  @Test
  func `an id run that runs into a word says what follows it`() throws {
    let scan = try MarkerSamples.scan("// @use-case:a.b#submiT\n")

    let message = try #require(scan.diagnostics.first?.message)
    #expect(message.hasPrefix("malformed marker id 'a.b#submi': 'T' follows the id directly"))
  }

  @Test
  func `nothing at all after the sentinel says no id follows`() throws {
    let scan = try MarkerSamples.scan("// @use-case: x\n")

    let message = try #require(scan.diagnostics.first?.message)
    #expect(message == "malformed marker id '': no marker id follows the sentinel")
  }

  @Test
  func `a sentinel directly after another is judged on its own`() throws {
    let text =
      "// @use-case:@use-case:\(MarkerSamples.identifier)\nx\n// \(MarkerSamples.close)\n"

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(scan.regions.count == 1)
    #expect(scan.diagnostics.map(\.code) == [.malformedMarkerIdentifier])
    #expect(MarkerSamples.content(of: region, in: text) == "x\n")
  }

  @Test
  func `a well-formed marker for a use case nobody has is still a region`() throws {
    let text = "// @use-case:example.nope#x\nz\n// @use-case:end example.nope#x\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.map(\.target.text) == ["example.nope#x"])
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `the id ends at the first character no id can hold`() throws {
    let cases: [(String, String)] = [
      ("<!--@use-case:a#b-->\n<p>x</p>\n<!--@use-case:end a#b-->\n", "a#b"),
      ("/*@use-case:a#b*/\nx\n/*@use-case:end a#b*/\n", "a#b"),
      (
        "\"# @use-case:a#b\\n\",\n\"x = 1\\n\",\n\"# @use-case:end a#b\\n\",\n",
        "a#b",
      ),
      ("// @use-case:a#b\u{A0}note\nx\n// @use-case:end a#b\u{A0}\n", "a#b"),
      ("// @use-case:a#b.\nx\n// @use-case:end a#b.\n", "a#b"),
      ("// @use-case:a#unit.b-\nx\n// @use-case:end a#unit.b-\n", "a#unit.b"),
    ]

    for (text, identifier) in cases {
      let scan = try MarkerSamples.scan(text)

      #expect(scan.regions.map(\.target.text) == [identifier], "in \(text.debugDescription)")
      #expect(scan.diagnostics.isEmpty, "in \(text.debugDescription)")
    }
  }

  @Test
  func `diagnostics are sorted by line as a number, whatever order they were found in`() throws {
    var lines = Array(repeating: "x", count: 12)
    lines[1] = "// @use-case:Bad"
    lines[8] = "// @use-case:Bad2"
    lines[9] = "// @use-case:Bad3"
    lines[10] = "// @use-case:a // @use-case:b"
    let text = lines.joined(separator: "\n") + "\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.diagnostics.compactMap { $0.position?.line } == [2, 9, 10, 11, 11])
  }

  @Test
  func `errors and warnings sort together by line`() throws {
    let text = "// @use-case:end example.a#b\n// @use-case:Bad\n// @use-case:example.c#d\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.diagnostics.map { $0.position?.line } == [1, 2, 3])
    #expect(scan.diagnostics.map(\.severity) == [.error, .warning, .error])
  }
}
