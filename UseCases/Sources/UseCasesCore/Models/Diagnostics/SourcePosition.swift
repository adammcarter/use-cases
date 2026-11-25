/// A place in an authored file, counted from 1. The column is there when the reader knows it.
struct SourcePosition: Hashable, Comparable, Sendable {
  let line: Int
  let column: Int?

  /// Makes a position, refusing a line or column below 1.
  init(
    line: Int,
    column: Int? = nil,
  ) throws(SourcePositionError) {
    guard line >= 1 else {
      throw .lineBelowOne(line)
    }

    if let column, column < 1 {
      throw .columnBelowOne(column)
    }

    self.line = line
    self.column = column
  }

  /// By line, then by column, a position with no column before one with a column.
  static func < (
    lhs: SourcePosition,
    rhs: SourcePosition,
  ) -> Bool {
    if lhs.line != rhs.line {
      return lhs.line < rhs.line
    }

    return lhs.column.precedesNilFirst(rhs.column)
  }
}
