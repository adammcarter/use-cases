import Testing
@testable import UseCasesCore

struct LineIndexTests {
  @Test(
    arguments: [
      ("", []),
      ("a", [0]),
      ("a\n", [0]),
      ("a\nb", [0, 2]),
      ("a\r\nb", [0, 3]),
      ("a\rb", [0, 2]),
      ("a\r\n", [0]),
      ("a\r", [0]),
      ("\n", [0]),
      ("\n\n", [0, 1]),
      ("\r\n\r\n", [0, 2]),
      ("\r\r", [0, 1]),
      ("\r\n\n", [0, 2]),
      ("a\n\rb", [0, 2, 3]),
    ] as [(String, [Int])],
  )
  func `each of CR, LF and CRLF is one break and the text after a final break is no line`(
    text: String,
    starts: [Int],
  ) {
    let index = LineIndex(Array(text.utf8))

    #expect(index.lineStarts == starts)
    #expect(index.lineCount == starts.count)
  }

  @Test
  func `a leading byte-order mark belongs to the first line`() {
    let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array("a\nb\n".utf8)
    let index = LineIndex(bytes)

    #expect(index.lineStarts == [0, 5])
    #expect(index.line(containing: 0) == 1)
    #expect(index.line(containing: 3) == 1)
  }

  @Test(
    arguments: [
      (0, 1), (1, 1), (2, 1), (3, 2), (4, 2), (5, 2), (6, 2), (7, 3), (8, 3),
    ] as [(Int, Int)],
  )
  func `a byte is on the line it is in, its break included`(
    offset: Int,
    line: Int,
  ) {
    let index = LineIndex(Array("ab\ncd\r\nef".utf8))

    #expect(index.line(containing: offset) == line)
  }

  @Test
  func `a line starts and ends where the next one starts`() {
    let index = LineIndex(Array("ab\ncd\r\nef".utf8))

    #expect(index.start(ofLine: 1) == 0)
    #expect(index.end(ofLine: 1) == 3)
    #expect(index.start(ofLine: 3) == 7)
    #expect(index.end(ofLine: 3) == 9)
    #expect(index.start(ofLine: 4) == 9)
    #expect(index.start(ofLine: 0) == 9)
  }
}
