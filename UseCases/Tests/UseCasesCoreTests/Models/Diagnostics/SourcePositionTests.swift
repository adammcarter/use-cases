import Testing
@testable import UseCasesCore

struct SourcePositionTests {
  @Test(
    arguments: [
      (1, nil),
      (1, 1),
      (7, 3),
      (Int.max, Int.max),
    ] as [(Int, Int?)],
  )
  func `a line and column from 1 are accepted`(
    line: Int,
    column: Int?,
  ) throws {
    let position = try SourcePosition(
      line: line,
      column: column,
    )

    #expect(position.line == line)
    #expect(position.column == column)
  }

  @Test(arguments: [0, -1, Int.min])
  func `a line below 1 is refused`(line: Int) {
    #expect(throws: SourcePositionError.lineBelowOne(line)) {
      try SourcePosition(line: line)
    }
  }

  @Test(arguments: [0, -1, Int.min])
  func `a column below 1 is refused`(column: Int) {
    #expect(throws: SourcePositionError.columnBelowOne(column)) {
      try SourcePosition(
        line: 1,
        column: column,
      )
    }
  }

  @Test(
    arguments: [
      (1, 5, 2, 1),
      (1, 1, 1, 2),
      (3, 1, 10, 1),
    ],
  )
  func `positions order by line, then by column`(
    firstLine: Int,
    firstColumn: Int,
    secondLine: Int,
    secondColumn: Int,
  ) throws {
    let first = try SourcePosition(
      line: firstLine,
      column: firstColumn,
    )
    let second = try SourcePosition(
      line: secondLine,
      column: secondColumn,
    )

    #expect(first < second)
    #expect(!(second < first))
  }

  @Test
  func `a column never outranks a later line`() throws {
    let early = try SourcePosition(line: 1)
    let late = try SourcePosition(line: 2)

    #expect(early < late)
  }
}
