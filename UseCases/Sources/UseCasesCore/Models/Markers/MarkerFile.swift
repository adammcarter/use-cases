/// One file's bytes with its lines and every sentinel in it: what a region is cut from.
struct MarkerFile: Sendable {
  let bytes: [UInt8]
  let lines: LineIndex

  /// Every sentinel in the file, well formed or not, in the order they appear.
  let sentinels: [MarkerSentinel]

  /// The lines that hold any sentinel, ascending, each once. A sentinel line is never content.
  let sentinelLines: [Int]

  /// The offset where each sentinel's token begins, in the same order as `sentinels`.
  let tokenStarts: [Int]

  /// The stretches between one sentinel line and the next.
  let lineGaps: MarkerContentGaps

  /// The stretches between one sentinel token and the next.
  let tokenGaps: MarkerContentGaps

  /// Gathers the sentinel lines and tokens, and measures the stretches between them.
  init(
    bytes: [UInt8],
    lines: LineIndex,
    sentinels: [MarkerSentinel],
  ) {
    self.bytes = bytes
    self.lines = lines
    self.sentinels = sentinels

    var found: [Int] = []

    for sentinel in sentinels where found.last != sentinel.line {
      found.append(sentinel.line)
    }

    sentinelLines = found
    tokenStarts = sentinels.map(\.tokenRange.lowerBound)
    lineGaps = MarkerContentGaps(
      byteRanges: zip(found, found.dropFirst()).map { above, below in
        lines.start(ofLine: above + 1) ..< lines.start(ofLine: below)
      },
      bytes: bytes,
    )
    tokenGaps = MarkerContentGaps(
      byteRanges: zip(sentinels, sentinels.dropFirst()).map { before, after in
        before.tokenRange.upperBound ..< after.tokenRange.lowerBound
      },
      bytes: bytes,
    )
  }

  /// The region a pair links, cut from the bytes by the rules of chapter 08.
  func region(
    of pair: MarkerPair,
    naming target: MarkerTarget,
  ) -> MarkerRegion {
    if pair.start.line == pair.end.line {
      return sameLineRegion(
        of: pair,
        naming: target,
      )
    }

    return lineRegion(
      of: pair,
      naming: target,
    )
  }

  /// The position of `value` in an ascending array that holds it.
  func position(
    of value: Int,
    in sorted: [Int],
  ) -> Int {
    var low = 0
    var high = sorted.count

    while low < high {
      let middle = (low + high) / 2

      if sorted[middle] < value {
        low = middle + 1
      } else {
        high = middle
      }
    }

    return low
  }
}
