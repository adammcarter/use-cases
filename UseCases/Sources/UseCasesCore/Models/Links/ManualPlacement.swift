/// Where a manual binding lands in its file: the lines it reports and the bytes it selects.
struct ManualPlacement: Equatable, Sendable {
  /// The first and last line, counted from 1.
  let lines: ClosedRange<Int>

  /// The selected bytes, end exclusive. Empty for an empty range or an empty file.
  let span: Range<Int>
}
