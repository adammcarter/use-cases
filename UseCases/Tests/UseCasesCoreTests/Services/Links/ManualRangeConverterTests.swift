import Testing
@testable import UseCasesCore

struct ManualRangeConverterTests {
  private let converter = ManualRangeConverter()

  private func place(
    _ text: String,
    from start: (line: Int, column: Int?),
    to end: (line: Int, column: Int?),
  ) throws(ManualRangeError) -> ManualPlacement {
    let positions = try? (
      SourcePosition(line: start.line, column: start.column),
      SourcePosition(line: end.line, column: end.column),
    )

    guard let positions else {
      throw .startsAfterEnd
    }

    return try converter.place(
      ManualRange(start: positions.0, end: positions.1),
      in: ManualContent(bytes: Array(text.utf8)),
    )
  }

  private func selected(
    _ placement: ManualPlacement,
    of text: String,
  ) -> String {
    String(bytes: Array(text.utf8)[placement.span], encoding: .utf8) ?? ""
  }

  @Test(
    arguments: [
      ("", 1),
      ("a", 1),
      ("a\n", 1),
      ("a\nb", 2),
      ("a\nb\n", 2),
      ("a\n\n", 2),
      ("\n", 1),
      ("a\r\nb\r\n", 2),
      ("a\rb\r", 2),
    ],
  )
  func `a whole file runs from line 1 to the last line holding any bytes`(
    case example: (text: String, last: Int),
  ) throws {
    let placement = try converter.place(
      nil,
      in: ManualContent(bytes: Array(example.text.utf8)),
    )

    #expect(placement.lines == 1 ... example.last)
    #expect(placement.span == 0 ..< example.text.utf8.count)
  }

  @Test
  func `a whole file may be binary`() throws {
    let placement = try converter.place(
      nil,
      in: ManualContent(bytes: [0xFF, 0x00, 0x0A, 0xFE]),
    )

    #expect(placement.lines == 1 ... 2)
    #expect(placement.span == 0 ..< 4)
  }

  @Test
  func `lines alone take whole lines and their breaks`() throws {
    let text = "one\ntwo\nthree\n"

    let middle = try place(text, from: (2, nil), to: (2, nil))
    let last = try place(text, from: (3, nil), to: (3, nil))

    #expect(selected(middle, of: text) == "two\n")
    #expect(middle.lines == 2 ... 2)
    #expect(selected(last, of: text) == "three\n")
  }

  @Test
  func `a last line without a break ends at the end of the file`() throws {
    let text = "one\ntwo"

    let placement = try place(text, from: (2, nil), to: (2, nil))

    #expect(selected(placement, of: text) == "two")
  }

  @Test
  func `columns count code points and include the end column's own bytes`() throws {
    let text = "first\n12ßé6\nlast\n"

    let placement = try place(text, from: (2, 3), to: (2, 5))

    #expect(selected(placement, of: text) == "ßé6")
  }

  @Test
  func `columns count scalars, not UTF-16 units or characters`() throws {
    let emoji = "😀a\n"
    let combining = "e\u{301}xy\n"

    let first = try place(emoji, from: (1, 2), to: (1, 2))
    let second = try place(combining, from: (1, 3), to: (1, 3))

    #expect(selected(first, of: emoji) == "a")
    #expect(selected(second, of: combining) == "x")
  }

  @Test
  func `a range may span lines and cut both ends`() throws {
    let text = "ab\ncd\nef\n"

    let placement = try place(text, from: (1, 2), to: (3, 1))

    #expect(selected(placement, of: text) == "b\ncd\ne")
    #expect(placement.lines == 1 ... 3)
  }

  @Test
  func `an omitted end column takes the rest of the line and its break`() throws {
    let text = "ab\r\ncd\r\n"

    let placement = try place(text, from: (1, 2), to: (1, nil))

    #expect(selected(placement, of: text) == "b\r\n")
  }

  @Test
  func `a line break is not part of the line's columns`() throws {
    let text = "ab\r\ncd\r\n"

    let atEnd = try place(text, from: (1, 1), to: (1, 2))

    #expect(selected(atEnd, of: text) == "ab")
    #expect(throws: ManualRangeError.endColumnOutsideLine(column: 3, line: 1, length: 2)) {
      try place(text, from: (1, 1), to: (1, 3))
    }
  }

  @Test
  func `a lone carriage return ends a line too`() throws {
    let text = "ab\rcd\r"

    let placement = try place(text, from: (2, 1), to: (2, 2))

    #expect(selected(placement, of: text) == "cd")
  }

  @Test
  func `a leading byte-order mark is not a column`() throws {
    let text = "\u{FEFF}abc\nxyz\n"

    let placement = try place(text, from: (1, 1), to: (1, 3))

    #expect(selected(placement, of: text) == "abc")
    #expect(throws: ManualRangeError.endColumnOutsideLine(column: 4, line: 1, length: 3)) {
      try place(text, from: (1, 1), to: (1, 4))
    }
  }

  @Test
  func `an omitted start column on line 1 starts at the very first byte`() throws {
    let text = "\u{FEFF}abc\nxyz\n"

    let placement = try place(text, from: (1, nil), to: (1, nil))

    #expect(placement.span == 0 ..< text.utf8.count - 4)
    #expect(Array(text.utf8)[placement.span].starts(with: [0xEF, 0xBB, 0xBF]))
  }

  @Test
  func `an end column one less than the start column is an empty range`() throws {
    let text = "abcd\n"

    let placement = try place(text, from: (1, 3), to: (1, 2))

    #expect(placement.span == 2 ..< 2)
    #expect(placement.lines == 1 ... 1)
  }

  @Test
  func `a start column may sit just past the end of its line`() throws {
    let text = "ab\ncd\n"

    let placement = try place(text, from: (1, 3), to: (1, nil))

    #expect(selected(placement, of: text) == "\n")
    #expect(throws: ManualRangeError.startColumnOutsideLine(column: 4, line: 1, length: 2)) {
      try place(text, from: (1, 4), to: (1, nil))
    }
  }

  @Test
  func `an end column on an empty line is outside it`() {
    #expect(throws: ManualRangeError.endColumnOutsideLine(column: 1, line: 2, length: 0)) {
      try place("a\n\nb\n", from: (1, nil), to: (2, 1))
    }
  }

  @Test
  func `a start column on an empty line is column 1`() throws {
    let text = "a\n\nb\n"

    let placement = try place(text, from: (2, 1), to: (2, nil))

    #expect(selected(placement, of: text) == "\n")
  }

  struct Reach: Sendable {
    let text: String
    let start: Int
    let end: Int
  }

  @Test(
    arguments: [
      Reach(text: "a\nb\n", start: 3, end: 3),
      Reach(text: "a\nb\n", start: 1, end: 3),
      Reach(text: "a\nb", start: 2, end: 3),
      Reach(text: "", start: 1, end: 1),
    ],
  )
  func `a line past the last line of the file is outside it`(example: Reach) {
    let lineCount = ManualContent(bytes: Array(example.text.utf8)).lines.lineCount
    let outside = example.end > lineCount ? example.end : example.start

    #expect(throws: ManualRangeError.lineOutsideFile(line: outside, lineCount: lineCount)) {
      try place(example.text, from: (example.start, nil), to: (example.end, nil))
    }
  }

  @Test(arguments: [[UInt8]([0xFF, 0x0A, 0x41]), [0xFF, 0xFE, 0x41, 0x00], [0xC3, 0x28]])
  func `a range cannot be cut from bytes that are not strict UTF-8`(bytes: [UInt8]) throws {
    let range = try ManualRange(
      start: SourcePosition(line: 1),
      end: SourcePosition(line: 1),
    )

    #expect(throws: ManualRangeError.notText) {
      try converter.place(
        range,
        in: ManualContent(bytes: bytes),
      )
    }
  }
}
