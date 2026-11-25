@testable import UseCasesCLI

/// A person at a terminal who types the answers they were given, and a probe told each time they
/// are asked something.
struct ProbingPrompter: Prompting {
  let prompter: MockPrompter
  let probe: ScopeProbe

  func show(_ text: String) async {
    await prompter.show(text)
  }

  func ask(_ question: String) async -> String? {
    await probe.record("asked")

    return await prompter.ask(question)
  }
}
