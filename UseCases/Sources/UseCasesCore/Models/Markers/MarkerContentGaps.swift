/// The stretches of a file between one separator and the next, where a separator is a line that
/// holds a sentinel (line mode) or a sentinel token (same-line mode).
///
/// A region's content is a run of consecutive gaps. Keeping the gaps once per file, with counts
/// that answer "is any of these gaps non-blank" and "which is the first or last one that holds
/// anything" in constant time, lets every region, nested however deeply, name its content by an
/// index range instead of holding a list of its own.
struct MarkerContentGaps: Sendable {
  /// Gap `k`: the bytes between separator `k` and separator `k + 1`. It may be empty.
  let byteRanges: [Range<Int>]

  /// `nonBlankBefore[k]` is how many of gaps `0..<k` hold a byte that is not TAB, LF, VT, FF, CR
  /// or SPACE.
  private let nonBlankBefore: [Int]

  /// `nextFilled[k]` is the first gap at or after `k` that holds any byte; `byteRanges.count`
  /// when none does.
  private let nextFilled: [Int]

  /// `previousFilled[k]` is the last gap at or before `k` that holds any byte; `-1` when none
  /// does.
  private let previousFilled: [Int]

  /// Measures the gaps against the file's bytes.
  init(
    byteRanges: [Range<Int>],
    bytes: [UInt8],
  ) {
    let count = byteRanges.count
    var blankCounts = [0]
    var previous: [Int] = []
    var next = Array(repeating: count, count: count + 1)
    var lastFilled = -1

    blankCounts.reserveCapacity(count + 1)
    previous.reserveCapacity(count)

    for (index, range) in byteRanges.enumerated() {
      let isBlank = bytes[range].allSatisfy(\.isBlankByte)

      blankCounts.append(blankCounts[index] + (isBlank ? 0 : 1))

      if !range.isEmpty {
        lastFilled = index
      }

      previous.append(lastFilled)
    }

    for index in stride(from: count - 1, through: 0, by: -1) {
      next[index] = byteRanges[index].isEmpty ? next[index + 1] : index
    }

    self.byteRanges = byteRanges
    nonBlankBefore = blankCounts
    nextFilled = next
    previousFilled = previous
  }

  /// Whether every byte in these gaps is blank, or there are none.
  func isBlank(_ gaps: Range<Int>) -> Bool {
    nonBlankBefore[gaps.upperBound] == nonBlankBefore[gaps.lowerBound]
  }

  /// The first of these gaps that holds any byte.
  func firstFilled(in gaps: Range<Int>) -> Int? {
    let found = nextFilled[gaps.lowerBound]

    return found < gaps.upperBound ? found : nil
  }

  /// The last of these gaps that holds any byte.
  func lastFilled(in gaps: Range<Int>) -> Int? {
    guard !gaps.isEmpty else {
      return nil
    }

    let found = previousFilled[gaps.upperBound - 1]

    return found >= gaps.lowerBound ? found : nil
  }

  /// The byte ranges of these gaps that hold any byte, in file order.
  func filledRanges(in gaps: Range<Int>) -> [Range<Int>] {
    gaps.compactMap { index in
      byteRanges[index].isEmpty ? nil : byteRanges[index]
    }
  }
}
