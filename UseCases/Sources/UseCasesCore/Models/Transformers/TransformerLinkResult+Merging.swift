extension TransformerLinkResult {
  /// One result from two for the same link: the worse status wins (chapter 10 §13), the tests of
  /// both are kept in order without repeats, and the note is the winner's, or the other's when
  /// the winner has none. On a tie the first result wins.
  func merging(_ other: TransformerLinkResult) -> TransformerLinkResult {
    let otherWins = other.status.severity > status.severity
    let winner = otherWins ? other : self
    let loser = otherWins ? self : other
    var tests = tests

    for test in other.tests where !tests.contains(test) {
      tests.append(test)
    }

    return TransformerLinkResult(
      link: link,
      status: winner.status,
      tests: tests,
      message: winner.message ?? loser.message,
    )
  }
}
