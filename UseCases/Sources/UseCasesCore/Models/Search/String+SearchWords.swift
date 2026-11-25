extension String {
  /// The words of the text, lower case: each run of letters and digits, so punctuation is not a
  /// word and `double-tap` is `double` and `tap`. Only the standard library decides what a letter
  /// is and what lower case is, so every system gets the same words.
  var searchWords: [String] {
    var words: [String] = []
    var current = ""

    for character in lowercased() {
      if character.isLetter || character.isNumber {
        current.append(character)
      } else if !current.isEmpty {
        words.append(current)
        current = ""
      }
    }

    if !current.isEmpty {
      words.append(current)
    }

    return words
  }
}
