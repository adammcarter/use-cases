@testable import UseCasesCLI

/// A person at a terminal who types the answers they were given, one for each question, and
/// remembers everything that was shown to them.
actor MockPrompter: Prompting {
  private var answers: [String]

  /// What was shown, in order: each line told, and each question asked.
  private(set) var transcript: [String] = []

  init(answers: [String] = []) {
    self.answers = answers
  }

  func show(_ text: String) {
    transcript.append(text)
  }

  func ask(_ question: String) -> String? {
    transcript.append(question)

    guard !answers.isEmpty else {
      return nil
    }

    return answers.removeFirst()
  }
}
