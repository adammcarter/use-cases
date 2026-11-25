import Testing
@testable import UseCasesCore

struct MarkerContentGapsTests {
  /// Bytes `a b` + spaces + `c`, cut into gaps at the places given.
  private func gaps(
    _ text: String,
    _ ranges: [Range<Int>],
  ) -> MarkerContentGaps {
    MarkerContentGaps(
      byteRanges: ranges,
      bytes: Array(text.utf8),
    )
  }

  @Test
  func `a gap is blank when it is empty or holds only TAB, LF, VT, FF, CR and SPACE`() {
    let table = gaps("a \t\r\n\u{0B}\u{0C}bc  d", [1 ..< 1, 1 ..< 7, 7 ..< 9, 9 ..< 12])

    #expect(table.isBlank(0 ..< 1))
    #expect(table.isBlank(0 ..< 2))
    #expect(!table.isBlank(0 ..< 3))
    #expect(table.isBlank(3 ..< 3))
    #expect(!table.isBlank(2 ..< 4))
  }

  @Test
  func `the first and last gap that hold any byte are found within a run of gaps`() {
    let table = gaps("abcdef", [0 ..< 0, 0 ..< 2, 2 ..< 2, 2 ..< 2, 2 ..< 5, 5 ..< 5])

    #expect(table.firstFilled(in: 0 ..< 6) == 1)
    #expect(table.lastFilled(in: 0 ..< 6) == 4)
    #expect(table.firstFilled(in: 2 ..< 4) == nil)
    #expect(table.lastFilled(in: 2 ..< 4) == nil)
    #expect(table.firstFilled(in: 2 ..< 6) == 4)
    #expect(table.lastFilled(in: 0 ..< 4) == 1)
    #expect(table.lastFilled(in: 0 ..< 0) == nil)
    #expect(table.firstFilled(in: 6 ..< 6) == nil)
  }

  @Test
  func `only the gaps that hold bytes are listed, in order`() {
    let table = gaps("abcdef", [0 ..< 0, 0 ..< 2, 2 ..< 2, 2 ..< 5])

    #expect(table.filledRanges(in: 0 ..< 4) == [0 ..< 2, 2 ..< 5])
    #expect(table.filledRanges(in: 2 ..< 3).isEmpty)
  }

  @Test
  func `no gaps at all is fine`() {
    let table = gaps("", [])

    #expect(table.isBlank(0 ..< 0))
    #expect(table.firstFilled(in: 0 ..< 0) == nil)
    #expect(table.filledRanges(in: 0 ..< 0).isEmpty)
  }
}
