import Testing
@testable import UseCasesCore

struct MarkerScannerMalformedTests {
  @Test(
    arguments: [
      ("// \(MarkerText.sentinel)\n", ""),
      ("// \(MarkerText.sentinel) example.a#b\n", ""),
      ("// \(MarkerText.sentinel)Bad_ID\n", ""),
      ("// \(MarkerText.sentinel)App.login#submit\n", ""),
      ("// \(MarkerText.sentinel)example.nope\n", "example.nope"),
      ("// \(MarkerText.sentinel)a#b#c\n", "a#b#c"),
      ("// \(MarkerText.sentinel)a#b.c.d\n", "a#b.c.d"),
      ("// \(MarkerText.sentinel)a..b#c\n", "a..b#c"),
      ("// \(MarkerText.sentinel).a#b\n", ".a#b"),
      ("// \(MarkerText.sentinel)a#\n", "a#"),
      ("// \(MarkerText.sentinel)#b\n", "#b"),
      ("// \(MarkerText.sentinel)-a#b\n", "-a#b"),
      ("// \(MarkerText.sentinel)a#-b\n", "a#-b"),
      ("// \(MarkerText.sentinel)end \n", ""),
      ("// \(MarkerText.sentinel)end\n", "end"),
      ("// \(MarkerText.sentinel)end Bad\n", ""),
      ("// \(MarkerText.sentinel)a.b#submiT\n", "a.b#submi"),
      ("// \(MarkerText.sentinel)a.b#c_d\n", "a.b#c"),
      ("// \(MarkerText.sentinel)a.b#c-A\n", "a.b#c"),
      ("// \(MarkerText.sentinel)end a.b#c_d\n", "a.b#c"),
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
      "// \(MarkerText.sentinel)a.b#submiT\nx\n// \(MarkerText.sentinel)end a.b#submiT\n",
      "// \(MarkerText.sentinel)a.b#c_d\nx\n// \(MarkerText.sentinel)end a.b#c_d\n",
      "// \(MarkerText.sentinel)a.b#c_d\nx\n// \(MarkerText.sentinel)end a.b#c\n",
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
    let text = "// \(MarkerText.sentinel)a.b#submiT\nx\n// \(MarkerText.sentinel)end a.b#submi\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.diagnostics.map(\.code) == [.malformedMarkerIdentifier, .markerWithoutStart])
    #expect(scan.regions.isEmpty)
  }

  @Test
  func `a trailing hyphen or dot trimmed off the id is fine when no word follows`() throws {
    let cases = [
      "<!--\(MarkerText.sentinel)a#b-->\nx\n<!--\(MarkerText.sentinel)end a#b-->\n",
      "// \(MarkerText.sentinel)a#b.\nx\n// \(MarkerText.sentinel)end a#b.\n",
      "// \(MarkerText.sentinel)a#b- note\nx\n// \(MarkerText.sentinel)end a#b-\n",
      "/*\(MarkerText.sentinel)a#b*/\nx\n/*\(MarkerText.sentinel)end a#b*/\n",
    ]

    for text in cases {
      let scan = try MarkerSamples.scan(text)

      #expect(scan.regions.map(\.target.text) == ["a#b"], "in \(text.debugDescription)")
      #expect(scan.diagnostics.isEmpty, "in \(text.debugDescription)")
    }
  }

  @Test
  func `an empty id says no id follows, and names the text that does`() throws {
    let scan = try MarkerSamples.scan("// \(MarkerText.sentinel)BAD\n")

    let message = try #require(scan.diagnostics.first?.message)
    #expect(message.hasPrefix("malformed marker id '': no marker id follows the sentinel"))
    #expect(message.contains("'BAD'"))
  }

  @Test
  func `an id run that runs into a word says what follows it`() throws {
    let scan = try MarkerSamples.scan("// \(MarkerText.sentinel)a.b#submiT\n")

    let message = try #require(scan.diagnostics.first?.message)
    #expect(message.hasPrefix("malformed marker id 'a.b#submi': 'T' follows the id directly"))
  }

  @Test
  func `nothing at all after the sentinel says no id follows`() throws {
    let scan = try MarkerSamples.scan("// \(MarkerText.sentinel) x\n")

    let message = try #require(scan.diagnostics.first?.message)
    #expect(message == "malformed marker id '': no marker id follows the sentinel")
  }

  @Test
  func `a sentinel directly after another is judged on its own`() throws {
    let text =
      "// \(MarkerText.sentinel)\(MarkerText.sentinel)\(MarkerSamples.identifier)\nx\n"
        + "// \(MarkerSamples.close)\n"

    let scan = try MarkerSamples.scan(text)

    let region = try #require(scan.regions.first)
    #expect(scan.regions.count == 1)
    #expect(scan.diagnostics.map(\.code) == [.malformedMarkerIdentifier])
    #expect(MarkerSamples.content(of: region, in: text) == "x\n")
  }

  @Test
  func `a well-formed marker for a use case nobody has is still a region`() throws {
    let text = "// \(MarkerText.sentinel)example.nope#x\nz\n"
      + "// \(MarkerText.sentinel)end example.nope#x\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.regions.map(\.target.text) == ["example.nope#x"])
    #expect(scan.diagnostics.isEmpty)
  }

  @Test
  func `the id ends at the first character no id can hold`() throws {
    let cases: [(String, String)] = [
      ("<!--\(MarkerText.sentinel)a#b-->\n<p>x</p>\n<!--\(MarkerText.sentinel)end a#b-->\n", "a#b"),
      ("/*\(MarkerText.sentinel)a#b*/\nx\n/*\(MarkerText.sentinel)end a#b*/\n", "a#b"),
      (
        "\"# \(MarkerText.sentinel)a#b\\n\",\n\"x = 1\\n\",\n"
          + "\"# \(MarkerText.sentinel)end a#b\\n\",\n",
        "a#b",
      ),
      (
        "// \(MarkerText.sentinel)a#b\u{A0}note\nx\n// \(MarkerText.sentinel)end a#b\u{A0}\n",
        "a#b",
      ),
      ("// \(MarkerText.sentinel)a#b.\nx\n// \(MarkerText.sentinel)end a#b.\n", "a#b"),
      (
        "// \(MarkerText.sentinel)a#unit.b-\nx\n// \(MarkerText.sentinel)end a#unit.b-\n",
        "a#unit.b",
      ),
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
    lines[1] = "// \(MarkerText.sentinel)Bad"
    lines[8] = "// \(MarkerText.sentinel)Bad2"
    lines[9] = "// \(MarkerText.sentinel)Bad3"
    lines[10] = "// \(MarkerText.sentinel)a // \(MarkerText.sentinel)b"
    let text = lines.joined(separator: "\n") + "\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.diagnostics.compactMap { $0.position?.line } == [2, 9, 10, 11, 11])
  }

  @Test
  func `errors and warnings sort together by line`() throws {
    let text = "// \(MarkerText.sentinel)end example.a#b\n// \(MarkerText.sentinel)Bad\n"
      + "// \(MarkerText.sentinel)example.c#d\n"

    let scan = try MarkerSamples.scan(text)

    #expect(scan.diagnostics.map { $0.position?.line } == [1, 2, 3])
    #expect(scan.diagnostics.map(\.severity) == [.error, .warning, .error])
  }
}
