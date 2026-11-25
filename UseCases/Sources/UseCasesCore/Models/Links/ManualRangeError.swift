/// Why a manual binding's range does not fit its file (chapter 08 "Manual bindings"). Each one
/// makes the workspace INVALID.
enum ManualRangeError: Error, Equatable, Sendable {
  /// A range cut from a file that is not strict UTF-8.
  case notText

  /// A line past the last line of the file; `lineCount` is 0 for an empty file.
  case lineOutsideFile(
    line: Int,
    lineCount: Int,
  )

  /// A start column past one beyond the end of its line, which is `length` code points long.
  case startColumnOutsideLine(
    column: Int,
    line: Int,
    length: Int,
  )

  /// An end column past the end of its line, which is `length` code points long; on an empty
  /// line no end column fits.
  case endColumnOutsideLine(
    column: Int,
    line: Int,
    length: Int,
  )

  /// The start comes after the end, after columns are counted.
  case startsAfterEnd
}
