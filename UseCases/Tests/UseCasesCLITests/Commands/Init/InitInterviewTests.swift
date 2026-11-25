import Testing
import UseCasesCore
@testable import UseCasesCLI

struct InitInterviewTests {
  private func interview(_ answers: [String]) -> (InitInterview, MockPrompter) {
    let prompter = MockPrompter(answers: answers)

    return (InitInterview(prompter: prompter), prompter)
  }

  // MARK: - The prompts

  @Test
  func `each question is the one of the chapter, ending in a bracket or a parenthesis`()
    async throws
  {
    let (interview, prompter) = interview(["", "", ""])

    _ = try await interview.form()
    _ = try await interview.prefix { _ in nil }
    _ = try await interview.hooks()

    #expect(await prompter.transcript == [
      "Full setup, or minimal? [full] ",
      "Root prefix? (blank for none) ",
      "Add hooks? commit / push / both / none [none] ",
    ])
  }

  // MARK: - The kind of setup

  @Test(arguments: [
    ("", InitForm.full), ("full", .full), ("1", .full), ("f", .full),
    ("minimal", .minimal), ("2", .minimal), ("m", .minimal), ("  minimal  ", .minimal),
  ])
  func `the kind is chosen by word, number or start, and blank is full`(
    answer: String,
    form: InitForm,
  ) async throws {
    let (interview, _) = interview([answer])

    #expect(try await interview.form() == form)
  }

  @Test
  func `an answer that names neither is told and asked again`() async throws {
    let (interview, prompter) = interview(["huge", "3", "m"])

    #expect(try await interview.form() == .minimal)
    #expect(await prompter.transcript == [
      "Full setup, or minimal? [full] ",
      "  pick a number, a word, or an unambiguous start of one",
      "Full setup, or minimal? [full] ",
      "  pick a number, a word, or an unambiguous start of one",
      "Full setup, or minimal? [full] ",
    ])
  }

  // MARK: - The prefix

  @Test
  func `a blank prefix is none and a good one is kept as typed`() async throws {
    let (none, _) = interview(["  "])
    let (named, _) = interview(["shop.app"])

    #expect(try await none.prefix { _ in nil } == nil)
    #expect(try await named.prefix { _ in nil } == "shop.app")
  }

  @Test
  func `a prefix that is refused is told why and asked again`() async throws {
    let (interview, prompter) = interview(["Shop", "shop_", "shop"])

    let prefix = try await interview.prefix { text in
      text == "shop" ? nil : "'\(text)' is not valid"
    }

    #expect(prefix == "shop")
    #expect(await prompter.transcript == [
      "Root prefix? (blank for none) ",
      "  'Shop' is not valid",
      "Root prefix? (blank for none) ",
      "  'shop_' is not valid",
      "Root prefix? (blank for none) ",
    ])
  }

  // MARK: - The hooks

  @Test(arguments: [
    ("", [HookName]()), ("none", []), ("4", []), ("n", []),
    ("commit", [.commit]), ("1", [.commit]), ("c", [.commit]),
    ("push", [.push]), ("2", [.push]), ("pu", [.push]),
    ("both", [.commit, .push]), ("3", [.commit, .push]), ("b", [.commit, .push]),
  ])
  func `the hooks are chosen by word, number or start, and blank is none`(
    answer: String,
    hooks: [HookName],
  ) async throws {
    let (interview, _) = interview([answer])

    #expect(try await interview.hooks() == hooks)
  }

  // MARK: - The end of the input

  @Test
  func `the end of the input stops every question`() async {
    let (interview, _) = interview([])

    await #expect(throws: InitInterviewError.inputEnded) {
      try await interview.form()
    }
    await #expect(throws: InitInterviewError.inputEnded) {
      try await interview.prefix { _ in nil }
    }
    await #expect(throws: InitInterviewError.inputEnded) {
      try await interview.hooks()
    }
  }

  @Test
  func `the end of the input while asking again stops it too`() async {
    let (interview, _) = interview(["huge"])

    await #expect(throws: InitInterviewError.inputEnded) {
      try await interview.form()
    }
  }
}
