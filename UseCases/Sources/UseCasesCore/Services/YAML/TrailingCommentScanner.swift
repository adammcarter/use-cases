/// Reads the source text after a plain scalar's end for a ` #` comment.
struct TrailingCommentScanner: TrailingCommentScanning {
  func finding(
    afterPlainScalar value: String,
    startingAt index: Int,
    in source: YAMLSourceText,
  ) -> TrailingCommentFinding {
    guard let end = source.plainScalarEnd(
      of: value,
      startingAt: index,
    ) else {
      return .lost
    }

    guard let comment = source.comment(after: end) else {
      return .noComment
    }

    return .cutsText(comment)
  }
}
