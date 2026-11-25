/// How far a link reaches from the line where its test name is written.
enum LinkBlock: String, Equatable, Sendable {
  /// The matching line only.
  case line
  /// From the match to the brace that closes the first `{` at or after it.
  case braces

  /// The 0-based index of the last line of the block that starts in `lines[index]`, at the
  /// scalar offset `column`. Braces are counted as characters: strings and comments are not
  /// understood. With no `{` after the match, or none that closes, the block is the matching
  /// line.
  func lastLine(
    in lines: [String],
    from index: Int,
    column: Int,
  ) -> Int {
    guard self == .braces else {
      return index
    }

    var depth = 0
    var isOpen = false

    for number in index ..< lines.count {
      let scalars = lines[number].unicodeScalars.dropFirst(number == index ? column : 0)

      for scalar in scalars {
        if scalar == "{" {
          depth += 1
          isOpen = true
        } else if scalar == "}", isOpen {
          depth -= 1

          if depth == 0 {
            return number
          }
        }
      }
    }

    return index
  }
}
