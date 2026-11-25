extension MarkerFile {
  /// Line mode: the whole lines strictly between the sentinel lines, leaving out every line that
  /// holds any sentinel.
  func lineRegion(
    of pair: MarkerPair,
    naming target: MarkerTarget,
  ) -> MarkerRegion {
    let firstBetween = pair.start.line + 1
    let lastBetween = pair.end.line - 1
    let content = MarkerContent(
      gaps: lineGaps,
      indices: position(
        of: pair.start.line,
        in: sentinelLines,
      ) ..< position(
        of: pair.end.line,
        in: sentinelLines,
      ),
    )

    return MarkerRegion(
      target: target,
      mode: .line,
      byteRange: lines.start(ofLine: firstBetween) ..< lines.start(ofLine: pair.end.line),
      lines: reportedLines(
        of: content,
        firstBetween: firstBetween,
        lastBetween: lastBetween,
      ),
      content: content,
    )
  }

  /// The first to the last content line; with no content line, the lines between (all of them
  /// sentinel lines); with no line between, the line after the start.
  private func reportedLines(
    of content: MarkerContent,
    firstBetween: Int,
    lastBetween: Int,
  ) -> ClosedRange<Int> {
    if let first = content.firstFilledGap, let last = content.lastFilledGap {
      return (sentinelLines[first] + 1) ... (sentinelLines[last + 1] - 1)
    }

    if firstBetween <= lastBetween {
      return firstBetween ... lastBetween
    }

    return firstBetween ... firstBetween
  }
}
