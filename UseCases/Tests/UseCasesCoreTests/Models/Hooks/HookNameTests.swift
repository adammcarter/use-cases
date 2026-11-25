import Testing
@testable import UseCasesCore

struct HookNameTests {
  @Test
  func `the hooks are commit then push, each at its git moment`() {
    #expect(HookName.allCases.map(\.rawValue) == ["commit", "push"])
    #expect(HookName.allCases.map(\.event) == ["pre-commit", "pre-push"])
    #expect(HookName.allCases.map(\.runs) == ["use-cases validate", "use-cases status --gate"])
  }

  @Test(arguments: [
    ([String](), [HookName]()),
    (["commit"], [.commit]),
    (["push", "commit"], [.commit, .push]),
    (["push", "push", "commit", "commit"], [.commit, .push]),
  ])
  func `the names are the hooks, once each, in the fixed order`(
    words: [String],
    hooks: [HookName],
  ) throws {
    #expect(try HookName.named(words) == hooks)
  }

  @Test
  func `a word that is not a hook is refused by name`() {
    #expect(throws: HookNameError.unknown(names: ["merge", "Commit"])) {
      try HookName.named(["commit", "merge", "Commit"])
    }
  }

  @Test
  func `the refusal says what the hooks are`() {
    #expect(
      HookNameError.unknown(names: ["merge"]).message
        == "unknown hook merge; the hooks are commit, push",
    )
  }
}
