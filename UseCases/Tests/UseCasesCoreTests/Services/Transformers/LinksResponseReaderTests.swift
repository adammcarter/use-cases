import Testing
@testable import UseCasesCore

struct LinksResponseReaderTests {
  private func read(_ text: String) throws(TransformerError) -> LinksAnswer {
    let object: AuthoredObject

    do {
      object = try AuthoredObject(
        JSONReader().read(text),
        at: "",
      )
    } catch {
      throw .malformedResponse(name: "test", reason: "the test's text is no object")
    }

    return try LinksResponseReader().read(
      object,
      from: "tools/links",
    )
  }

  private func malformed(_ reason: String) -> TransformerError {
    .malformedResponse(name: "tools/links", reason: reason)
  }

  @Test
  func `a link is read member by member, and its text is kept on one line`() throws {
    let answer = try read(
      """
      {"contract": 1, "diagnostics": ["one", "two"], "links": [
        {"use_case": "app.toggle", "route": "manual", "binding": "t", "role": "validation",
         "file": "a.js", "range": {"start": 5, "end": 7}}
      ]}
      """,
    )

    let link = try #require(answer.links.first)

    #expect(link.useCase == "app.toggle")
    #expect(link.route == "manual")
    #expect(link.binding == "t")
    #expect(link.role == "validation")
    #expect(link.file == "a.js")
    #expect(link.range == TransformerLinkRange(start: 5, end: 7))
    #expect(
      link.text == #"{"binding":"t","file":"a.js","range":{"end":7,"start":5},"role":"validation","#
        + #""route":"manual","use_case":"app.toggle"}"#,
    )
    #expect(answer.diagnostics == ["one", "two"])
  }

  @Test
  func `members it does not know are ignored, in the response and in a link`() throws {
    let answer = try read(
      """
      {"contract": 1, "links": [{"use_case": "app.toggle", "binding": "t", "role": "implementation",
        "file": "a.js", "confidence": 0.9, "range": {"start": 1, "end": 2, "columns": [1, 4]}}],
       "diagnostics": [], "elapsed_ms": 12}
      """,
    )

    #expect(answer.links.count == 1)
    #expect(answer.links.first?.range == TransformerLinkRange(start: 1, end: 2))
  }

  @Test
  func `a link with no range covers the whole file, and one with half a range is kept as it is`()
    throws
  {
    let answer = try read(
      """
      {"contract": 1, "diagnostics": [], "links": [
        {"use_case": "a", "binding": "b", "role": "implementation", "file": "f"},
        {"use_case": "a", "binding": "b", "role": "implementation", "file": "f",
         "range": {"start": 3}},
        {"use_case": "a", "binding": "b", "role": "implementation", "file": "f", "range": {}}
      ]}
      """,
    )

    #expect(answer.links.map(\.range) == [
      nil,
      TransformerLinkRange(start: 3, end: nil),
      TransformerLinkRange(start: nil, end: nil),
    ])
  }

  @Test
  func `a link with members missing is still read: the checker finds what is wrong`() throws {
    let answer = try read(#"{"contract": 1, "diagnostics": [], "links": [{}]}"#)

    let link = try #require(answer.links.first)

    #expect(link.useCase == nil)
    #expect(link.binding == nil)
    #expect(link.role == nil)
    #expect(link.file == nil)
  }

  @Test
  func `no links is no links, and no diagnostics is not yet an error`() throws {
    let empty = try read(#"{"contract": 1, "links": [], "diagnostics": []}"#)
    let silent = try read(#"{"contract": 1, "links": []}"#)

    #expect(empty.links.isEmpty)
    #expect(empty.diagnostics == [])
    #expect(silent.diagnostics == nil)
  }

  @Test(
    arguments: [
      (#"{"contract": 1, "diagnostics": []}"#, "links: this is required"),
      (#"{"contract": 1, "links": {}, "diagnostics": []}"#, "links: this must be a list"),
      (#"{"contract": 1, "links": [1], "diagnostics": []}"#, "links[0]: this must be a mapping"),
      (
        #"{"contract": 1, "links": [{"use_case": 5}], "diagnostics": []}"#,
        "links[0].use_case: this must be text",
      ),
      (
        #"{"contract": 1, "links": [{"file": ["a"]}], "diagnostics": []}"#,
        "links[0].file: this must be text",
      ),
      (
        #"{"contract": 1, "links": [{"range": 3}], "diagnostics": []}"#,
        "links[0].range: this must be a mapping",
      ),
      (
        #"{"contract": 1, "links": [{"range": {"start": "1"}}], "diagnostics": []}"#,
        "links[0].range.start: this must be a whole number",
      ),
      (
        #"{"contract": 1, "links": [{"range": {"end": 2.5}}], "diagnostics": []}"#,
        "links[0].range.end: this must be a whole number",
      ),
      (
        #"{"contract": 1, "links": [], "diagnostics": "none"}"#,
        "diagnostics: this must be a list",
      ),
      (
        #"{"contract": 1, "links": [], "diagnostics": [1]}"#,
        "diagnostics[0]: this must be text",
      ),
    ],
  )
  func `a known member of the wrong type is malformed, and says where`(
    text: String,
    reason: String,
  ) {
    #expect(throws: malformed(reason)) {
      try read(text)
    }
  }
}
