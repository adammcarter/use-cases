import Testing
@testable import UseCasesCore

struct YAMLSourceTextTests {
  @Test(arguments: [
    "a\nb\nc", "a\r\nb\r\nc", "a\rb\rc", "a\u{85}b\u{85}c", "a\u{2028}b\u{2028}c",
    "a\u{2029}b\u{2029}c", "a\nb\r\nc",
  ])
  func `every line break libyaml knows starts a new line`(text: String) {
    let source = YAMLSourceText(text)

    #expect(source.index(line: 1, column: 1) == 0)
    #expect(source.index(line: 2, column: 1).map(source.line(at:)) == 2)
    #expect(source.index(line: 3, column: 1).map(source.line(at:)) == 3)
  }

  @Test
  func `a carriage return and a line feed together are one break`() {
    let source = YAMLSourceText("a\r\nb")

    #expect(source.index(line: 2, column: 1) == 3)
    #expect(source.index(line: 3, column: 1) == nil)
  }

  @Test
  func `a column counts Unicode scalars, not bytes or characters`() {
    let source = YAMLSourceText("\u{E9}: 😀 x\nb")

    #expect(source.index(line: 1, column: 6) == 5)
    #expect(source.index(line: 2, column: 1) == 7)
  }

  @Test(arguments: [(0, 1), (1, 1), (2, 1), (3, 2), (5, 2), (6, 3), (8, 3), (9, 4)])
  func `a position is on the line it falls in`(
    index: Int,
    line: Int,
  ) {
    let source = YAMLSourceText("ab\ncd\nef\n")

    #expect(source.line(at: index) == line)
  }

  @Test(arguments: [(0, 0), (1, 0), (0, 4), (5, 1)])
  func `a mark outside the text points nowhere`(
    line: Int,
    column: Int,
  ) {
    let source = YAMLSourceText("ab\ncd")

    #expect(source.index(
      line: line,
      column: column,
    ) == nil)
  }

  @Test
  func `a mark at the very end of the text is a position`() {
    let source = YAMLSourceText("ab\ncd")

    #expect(source.index(line: 2, column: 3) == 5)
  }

  @Test
  func `anchors are skipped and the content found`() {
    let source = YAMLSourceText("&a &b\n  x")
    let properties = source.properties(startingAt: 0)

    #expect(properties == YAMLNodeProperties(contentStart: 8, tagIndex: nil))
  }

  @Test(arguments: [("!!str x", 0), ("&a !!str x", 3), ("&a\n  !note x", 5), ("! x", 0)])
  func `a tag is found after any anchors`(
    text: String,
    tagIndex: Int,
  ) {
    let properties = YAMLSourceText(text).properties(startingAt: 0)

    #expect(properties.tagIndex == tagIndex)
  }

  @Test
  func `a node with no properties begins where it is`() {
    #expect(YAMLSourceText("plain").properties(startingAt: 0) == YAMLNodeProperties(
      contentStart: 0,
      tagIndex: nil,
    ))
  }

  @Test(arguments: [
    ("key: Check medal #4 shows", "Check medal", 5, 16),
    ("- one\n  two", "one two", 2, 11),
    ("- one\n\n  two", "one two", 2, 12),
    ("- one   \n   two  \n", "one two", 2, 15),
    ("- one\r\n  two\r\n", "one two", 2, 12),
    ("x", "x", 0, 1),
  ])
  func `a plain scalar's end is found even where lines were folded`(
    text: String,
    value: String,
    start: Int,
    end: Int,
  ) {
    let source = YAMLSourceText(text)

    #expect(source.plainScalarEnd(of: value, startingAt: start) == end)
  }

  @Test
  func `a plain scalar that is not in the source has no end`() {
    #expect(YAMLSourceText("abc").plainScalarEnd(of: "abd", startingAt: 0) == nil)
  }

  @Test(arguments: [
    ("a  # note", 1, "# note", 1),
    ("a\t# note", 1, "# note", 1),
    ("a # note   \nb", 1, "# note", 1),
    ("a #", 1, "#", 1),
    ("a # one # two", 1, "# one # two", 1),
    ("a\nb # note", 3, "# note", 2),
  ])
  func `a comment set apart by white space is found`(
    text: String,
    after: Int,
    comment: String,
    line: Int,
  ) {
    let found = YAMLSourceText(text).comment(after: after)

    #expect(found == YAMLComment(text: comment, line: line))
  }

  @Test(arguments: [("a", 1), ("a\n# next line", 1), ("a: b", 1), ("a,# x", 1), ("a]  # x", 1)])
  func `anything else after a scalar is not a comment`(
    text: String,
    after: Int,
  ) {
    #expect(YAMLSourceText(text).comment(after: after) == nil)
  }

  @Test
  func `the lines of a text can be read back without their breaks`() {
    let source = YAMLSourceText("ab\r\ncd\n\nef")

    #expect(source.lineCount == 4)
    #expect(source.scalars(ofLine: 1) == ["a", "b"])
    #expect(source.scalars(ofLine: 2) == ["c", "d"])
    #expect(source.scalars(ofLine: 3) == [])
    #expect(source.scalars(ofLine: 4) == ["e", "f"])
    #expect(source.scalars(ofLine: 0) == [])
    #expect(source.scalars(ofLine: 5) == [])
  }

  @Test(arguments: [
    ("&x # c\n  !!str 42", 9),
    ("&x\n  # c\n  !!str 42", 11),
    ("&x # c\n  !t v", 9),
    ("&x # c\n# d\n\n  !t v", 14),
    ("&x &y # c\n  !t v", 12),
  ])
  func `a tag is found after anchors and comments`(
    text: String,
    tagIndex: Int,
  ) {
    let properties = YAMLSourceText(text).properties(startingAt: 0)

    #expect(properties.tagIndex == tagIndex)
  }

  @Test(arguments: [
    ("&x # c\n  Dark mode", 9),
    ("&x\n  # c\n  Dark mode", 11),
    ("&x # c\n# d\n\n  Dark mode", 14)
  ])
  func `the text after anchors and comments is where the content begins`(
    text: String,
    contentStart: Int,
  ) {
    let properties = YAMLSourceText(text).properties(startingAt: 0)

    #expect(properties == YAMLNodeProperties(contentStart: contentStart, tagIndex: nil))
  }

  @Test
  func `a hash right after an anchor name is part of the name`() {
    let properties = YAMLSourceText("&x#c Dark mode").properties(startingAt: 0)

    #expect(properties.contentStart == 5)
  }
}
