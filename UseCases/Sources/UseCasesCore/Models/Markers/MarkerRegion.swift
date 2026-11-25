/// The code one well-paired marker links (chapter 08 "The linked region").
struct MarkerRegion: Hashable, Sendable {
  /// The use case, route and binding the marker names. None of them is known to exist.
  let target: MarkerTarget
  let mode: MarkerMode

  /// The region's bytes in the file, end exclusive: in line mode every byte of the whole lines
  /// between the two sentinel lines, nested sentinel lines included; in same-line mode the bytes
  /// between the two tokens. This is the locator span (chapter 11 §89.5).
  let byteRange: Range<Int>

  /// The lines the link reports: the first to the last content line in line mode, the sentinel
  /// line in same-line mode. A line-mode region with no lines between its sentinels is reported
  /// at the line after the start, as that line to that line. When the only lines between are
  /// sentinel lines, the range covers those lines.
  let lines: ClosedRange<Int>

  /// What the link holds, named without being listed.
  let content: MarkerContent

  /// The bytes the link holds, in file order: `byteRange` less every line that holds a sentinel
  /// (line mode) or every sentinel token (same-line mode). Empty pieces are left out. Joining the
  /// bytes of these ranges gives the linked content.
  ///
  /// This is worked out on each call, in proportion to the pieces it returns. A region with
  /// thousands of nested markers has thousands of pieces, so ask for it when the content is
  /// needed, not for every region.
  var contentRanges: [Range<Int>] {
    content.ranges
  }

  /// Whether the content is nothing, or only TAB, LF, VT, FF, CR and SPACE.
  var isEmpty: Bool {
    content.isBlank
  }

  /// The first reported line: the `<start-line>` of the link key.
  var startLine: Int {
    lines.lowerBound
  }
}
