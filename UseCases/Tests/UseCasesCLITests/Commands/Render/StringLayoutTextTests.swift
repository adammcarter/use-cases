import Testing
@testable import UseCasesCLI

struct StringLayoutTextTests {
  @Test
  func `width is counted in Unicode scalars, never in what a terminal shows`() {
    #expect("abc".scalarCount == 3)
    #expect("→".scalarCount == 1)
    #expect("e\u{301}".scalarCount == 2)
    #expect("👨‍👩‍👧".scalarCount == 5)
    #expect("".scalarCount == 0)
  }

  @Test(arguments: [
    ("a b", "a b"),
    ("  a   b  ", "a b"),
    ("a\nb\tc\r\nd", "a b c d"),
    ("one\u{A0}two", "one two"),
    ("", ""),
    (" \n ", ""),
  ])
  func `white space of any kind between words is one space, and none at the ends`(
    text: String,
    expected: String,
  ) {
    #expect(text.collapsingWhitespace == expected)
  }

  @Test(arguments: [
    ("ab", 2, "ab"),
    ("ab", 5, "ab   "),
    ("abc", 2, "abc"),
    ("", 3, "   "),
    ("→→", 4, "→→  "),
    ("e\u{301}", 3, "e\u{301} "),
    ("x", -4, "x"),
  ])
  func `padding fills to the width in scalars and never cuts`(
    text: String,
    width: Int,
    expected: String,
  ) {
    #expect(text.padded(toScalars: width) == expected)
  }

  @Test
  func `only spaces at the end are dropped`() {
    #expect("a b  ".withoutTrailingSpaces == "a b")
    #expect("  a".withoutTrailingSpaces == "  a")
    #expect("   ".withoutTrailingSpaces.isEmpty)
    #expect("a\n".withoutTrailingSpaces == "a\n")
  }

  @Test(arguments: [
    ("one two three", 7, ["one two", "three"]),
    ("one two three", 13, ["one two three"]),
    ("one two three", 12, ["one two", "three"]),
    ("one two three", 3, ["one", "two", "thr", "ee"]),
    ("", 10, [""]),
    ("   ", 10, [""]),
    ("a\nb", 10, ["a b"]),
    ("abcdefghij", 4, ["abcd", "efgh", "ij"]),
    ("ab abcdefghij", 4, ["ab", "abcd", "efgh", "ij"]),
    ("abcdefgh", 4, ["abcd", "efgh"]),
    ("a b", 0, ["a", "b"]),
    ("a b", -3, ["a", "b"]),
    ("→→→→→ →", 3, ["→→→", "→→", "→"]),
  ])
  func `text breaks only at spaces, and a word too long for a line breaks where it ends`(
    text: String,
    width: Int,
    expected: [String],
  ) {
    #expect(text.wrapped(toScalars: width) == expected)
  }

  @Test
  func `no line is wider than the width, whatever the text`() {
    let text = "a  verylongword\n" + String(repeating: "→", count: 40) + " b c"

    for width in 1 ... 12 {
      #expect(text.wrapped(toScalars: width).allSatisfy { line in
        line.scalarCount <= width
      })
    }
  }
}
