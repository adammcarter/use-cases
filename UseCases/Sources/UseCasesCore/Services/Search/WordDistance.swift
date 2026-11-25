/// How many typos one word is from another: a wrong, a missing, an extra or a swapped letter each
/// count one.
struct WordDistance: Sendable {
  /// The number of typos between the words when it is `limit` or fewer; otherwise `nil`.
  func between(
    _ first: [Character],
    _ second: [Character],
    atMost limit: Int,
  ) -> Int? {
    guard abs(first.count - second.count) <= limit else {
      return nil
    }

    let found = restricted(first, second)

    return found <= limit ? found : nil
  }

  /// The optimal string alignment distance: the edit distance where two letters next to each
  /// other may also be swapped for one edit.
  private func restricted(
    _ first: [Character],
    _ second: [Character],
  ) -> Int {
    guard !first.isEmpty, !second.isEmpty else {
      return max(first.count, second.count)
    }

    var rows = [[Int]](
      repeating: [Int](repeating: 0, count: second.count + 1),
      count: first.count + 1,
    )

    for row in 0 ... first.count {
      rows[row][0] = row
    }

    for column in 0 ... second.count {
      rows[0][column] = column
    }

    for row in 1 ... first.count {
      for column in 1 ... second.count {
        let cost = first[row - 1] == second[column - 1] ? 0 : 1
        var best = min(
          rows[row - 1][column] + 1,
          rows[row][column - 1] + 1,
          rows[row - 1][column - 1] + cost,
        )

        if row > 1, column > 1,
           first[row - 1] == second[column - 2],
           first[row - 2] == second[column - 1]
        {
          best = min(best, rows[row - 2][column - 2] + 1)
        }

        rows[row][column] = best
      }
    }

    return rows[first.count][second.count]
  }
}
