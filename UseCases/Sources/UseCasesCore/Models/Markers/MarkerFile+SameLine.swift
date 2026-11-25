extension MarkerFile {
  /// Same-line mode: the bytes strictly between the two tokens, less the bytes of every sentinel
  /// token inside them. The comment syntax around a nested token stays.
  func sameLineRegion(
    of pair: MarkerPair,
    naming target: MarkerTarget,
  ) -> MarkerRegion {
    MarkerRegion(
      target: target,
      mode: .sameLine,
      byteRange: pair.start.tokenRange.upperBound ..< pair.end.tokenRange.lowerBound,
      lines: pair.start.line ... pair.start.line,
      content: MarkerContent(
        gaps: tokenGaps,
        indices: position(
          of: pair.start.tokenRange.lowerBound,
          in: tokenStarts,
        ) ..< position(
          of: pair.end.tokenRange.lowerBound,
          in: tokenStarts,
        ),
      ),
    )
  }
}
