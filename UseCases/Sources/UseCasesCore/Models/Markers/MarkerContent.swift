/// The content of one region: a run of consecutive gaps of its file, named by index.
///
/// Every region of a file shares the file's gaps, so a region costs two indices however deeply
/// markers nest inside it. The pieces themselves are worked out only when asked for.
struct MarkerContent: Hashable, Sendable {
  private let gaps: MarkerContentGaps

  /// The gaps this content is made of.
  let gapIndices: Range<Int>

  /// Names the gaps `indices` of `gaps`.
  init(
    gaps: MarkerContentGaps,
    indices: Range<Int>,
  ) {
    self.gaps = gaps
    gapIndices = indices
  }

  /// Whether the content is nothing, or only TAB, LF, VT, FF, CR and SPACE.
  var isBlank: Bool {
    gaps.isBlank(gapIndices)
  }

  /// The first gap that holds any byte, if any does.
  var firstFilledGap: Int? {
    gaps.firstFilled(in: gapIndices)
  }

  /// The last gap that holds any byte, if any does.
  var lastFilledGap: Int? {
    gaps.lastFilled(in: gapIndices)
  }

  /// The byte ranges that make up the content, in file order, empty pieces left out. This walks
  /// the gaps, so it costs time and memory in proportion to the pieces it returns.
  var ranges: [Range<Int>] {
    gaps.filledRanges(in: gapIndices)
  }

  /// Two contents are equal when they name the same gaps, ending in the same bytes: the same
  /// stretch of the same file.
  static func == (
    lhs: MarkerContent,
    rhs: MarkerContent,
  ) -> Bool {
    lhs.gapIndices == rhs.gapIndices && lhs.edges == rhs.edges
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(gapIndices)
    hasher.combine(edges.first)
    hasher.combine(edges.last)
  }

  /// The first and the last gap's bytes.
  private var edges: [Range<Int>] {
    guard let first = gapIndices.first, let last = gapIndices.last else {
      return []
    }

    return [gaps.byteRanges[first], gaps.byteRanges[last]]
  }
}
