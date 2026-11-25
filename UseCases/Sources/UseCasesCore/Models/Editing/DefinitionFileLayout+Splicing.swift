extension DefinitionFileLayout {
  /// The lines of the file with one use case written as `replacement`: nothing outside the use
  /// case changes, and the blank lines after it stay as they were, unless the replacement ends
  /// in blank lines of its own, which are text.
  func replacing(
    _ number: Int,
    with replacement: [String],
  ) -> [String] {
    let item = items[number]
    let gap = replacement.last == "" ? [] : Array(lines[item.ownEnd ..< item.gapEnd])

    return Array(lines[..<item.start]) + replacement + gap + Array(lines[item.gapEnd...])
  }

  /// The lines of the file without one use case, its comments directly above it, and the blank
  /// lines after it. Taking out the last one takes the gap before it too, so the file does not
  /// end with a blank line it did not have.
  func removing(_ number: Int) -> [String] {
    let item = items[number]
    var first = item.attachedStart

    if number == items.count - 1, number > 0 {
      let earlier = items[number - 1]

      while first > earlier.contentEnd, lines[first - 1].isBlank {
        first -= 1
      }
    }

    // The last use case leaves its own gap behind, as the gap before it goes: the file keeps the
    // blank lines it had after its use cases.
    let resume = number == items.count - 1 && number > 0 ? item.contentEnd : item.gapEnd

    return Array(lines[..<first]) + Array(lines[resume...])
  }

  /// The lines of the file with a use case after the last one, set apart as the file sets its
  /// use cases apart.
  func appending(_ addition: [String]) -> [String] {
    guard let last = items.last else {
      return lines + addition
    }

    let gap = addition.last == "" ? last.gapEnd : last.contentEnd

    return Array(lines[..<last.contentEnd])
      + Array(repeating: "", count: separator)
      + addition
      + Array(lines[gap...])
  }

  /// How many blank lines the file puts between its use cases: what follows its first use case
  /// that has another after it, and none when no use case is followed by another or the last
  /// one ends in a block that keeps its blank lines.
  private var separator: Int {
    guard let last = items.last, !last.keepsBlankLines else {
      return 0
    }

    return items.dropLast().first { item in
      !item.keepsBlankLines
    }?.gap ?? 0
  }
}

private extension String {
  var isBlank: Bool {
    unicodeScalars.allSatisfy { scalar in
      scalar == " " || scalar == "\t" || scalar == "\r"
    }
  }
}
