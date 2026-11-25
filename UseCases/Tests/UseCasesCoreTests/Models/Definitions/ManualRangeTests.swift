import Testing
@testable import UseCasesCore

struct ManualRangeTests {
  private func range(
    _ start: (line: Int, column: Int?),
    _ end: (line: Int, column: Int?),
  ) throws -> ManualRange {
    try ManualRange(
      start: SourcePosition(line: start.line, column: start.column),
      end: SourcePosition(line: end.line, column: end.column),
    )
  }

  @Test
  func `an end column one less than the start column on one line is an empty range, not backwards`()
    throws
  {
    #expect(try !range((1, 3), (1, 2)).startsAfterEnd)
  }

  @Test
  func `an end column two less than the start column starts after it ends`() throws {
    #expect(try range((1, 4), (1, 2)).startsAfterEnd)
  }

  @Test
  func `a range that ends where or after it starts, or has a missing column, is forwards`() throws {
    #expect(try !range((1, 2), (1, 2)).startsAfterEnd)
    #expect(try !range((1, 3), (1, nil)).startsAfterEnd)
    #expect(try !range((1, nil), (1, 2)).startsAfterEnd)
  }

  @Test
  func `on different lines only the lines decide`() throws {
    #expect(try !range((1, 9), (2, 1)).startsAfterEnd)
    #expect(try range((3, 1), (2, 9)).startsAfterEnd)
  }
}
