/// Which of the words offered an answer names.
enum InitChoice {
  /// The word an answer names: the word itself, its number in the list as it was shown, or the
  /// start of exactly one of the words. An exact word wins over a number, and a number over a
  /// start. An empty answer, an unknown one and one that starts several words name nothing.
  static func word(
    for answer: String,
    among words: [String],
  ) -> String? {
    guard !answer.isEmpty else {
      return nil
    }

    if words.contains(answer) {
      return answer
    }

    if answer.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }), let number = Int(answer) {
      return words.indices.contains(number - 1) ? words[number - 1] : nil
    }

    let starting = words.filter { word in
      word.hasPrefix(answer)
    }

    return starting.count == 1 ? starting.first : nil
  }
}
