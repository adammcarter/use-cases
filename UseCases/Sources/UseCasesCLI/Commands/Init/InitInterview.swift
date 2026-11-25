import UseCasesCore

/// Asks what the flags of `init` did not say (chapter 17 §1): the kind of setup, the root prefix
/// and the hooks, one question each. A prompt ends in `]` or `)`, so a script driving a terminal
/// knows when it is being asked. An answer that cannot be taken is told and asked again; the end
/// of the input stops the questions.
struct InitInterview {
  private static let formPrompt = "Full setup, or minimal? [full] "
  private static let prefixPrompt = "Root prefix? (blank for none) "
  private static let hooksPrompt = "Add hooks? commit / push / both / none [none] "
  private static let forms = ["full", "minimal"]
  private static let hooks = ["commit", "push", "both", "none"]
  private static let pickAgain = "  pick a number, a word, or an unambiguous start of one"

  private let prompter: any Prompting

  init(prompter: any Prompting) {
    self.prompter = prompter
  }

  func form() async throws(InitInterviewError) -> InitForm {
    let word = try await choose(
      Self.formPrompt,
      among: Self.forms,
      default: "full",
    )

    return word == "minimal" ? .minimal : .full
  }

  /// - Parameter problem: Says what is wrong with a prefix, or `nil` when it can be used.
  /// - Returns: The prefix typed, or `nil` for none.
  func prefix(problem: (String) -> String?) async throws(InitInterviewError) -> String? {
    while true {
      let text = try await answer(Self.prefixPrompt)

      guard !text.isEmpty else {
        return nil
      }

      guard let reason = problem(text) else {
        return text
      }

      await prompter.show("  " + reason)
    }
  }

  func hooks() async throws(InitInterviewError) -> [HookName] {
    let word = try await choose(
      Self.hooksPrompt,
      among: Self.hooks,
      default: "none",
    )

    switch word {
    case "both":
      return HookName.allCases
    case "none":
      return []
    default:
      return HookName(rawValue: word).map { [$0] } ?? []
    }
  }

  private func choose(
    _ question: String,
    among words: [String],
    default fallback: String,
  ) async throws(InitInterviewError) -> String {
    while true {
      let text = try await answer(question)

      if text.isEmpty {
        return fallback
      }

      if let word = InitChoice.word(
        for: text,
        among: words,
      ) {
        return word
      }

      await prompter.show(Self.pickAgain)
    }
  }

  private func answer(_ question: String) async throws(InitInterviewError) -> String {
    guard let line = await prompter.ask(question) else {
      throw .inputEnded
    }

    return line.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
