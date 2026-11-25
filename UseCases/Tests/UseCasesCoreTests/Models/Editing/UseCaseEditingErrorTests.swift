import Testing
@testable import UseCasesCore

struct UseCaseEditingErrorTests {
  @Test(arguments: [
    (UseCaseEditingError.notAUseCase(name: "stdin"), UseCaseEditingError.Kind.usage),
    (.noGroup(identifier: "a"), .usage),
    (.needsGroup(identifier: "a.b", namespace: "a"), .usage),
    (.unknown(identifier: "a.b.c"), .usage),
    (.approvalNotBySave(identifier: "a.b.c"), .usage),
    (.invalidUseCase(name: "stdin", problems: ["x"]), .invalid),
    (.unsupportedLayout(file: "f.yml", reason: "r"), .refused),
    (.wouldNotReadBack(file: "f.yml"), .refused),
  ])
  func `a refusal is told to a script as usage, invalid or refused`(
    error: UseCaseEditingError,
    kind: UseCaseEditingError.Kind,
  ) {
    #expect(error.kind == kind)
  }

  @Test
  func `the messages carry the words the design pins`() {
    #expect(UseCaseEditingError.noGroup(identifier: "orphan").message.contains("has no group"))
    #expect(
      UseCaseEditingError.needsGroup(identifier: "a.b", namespace: "a").message
        .contains("need a group"),
    )
    #expect(UseCaseEditingError.notAUseCase(name: "stdin").message.contains("full id"))
    #expect(
      UseCaseEditingError.notAUseCase(name: "stdin").message
        .contains("one mapping with its full id"),
    )
    #expect(
      UseCaseEditingError.approvalNotBySave(identifier: "a.b.c").message.contains("never by save"),
    )
    #expect(UseCaseEditingError.unknown(identifier: "a.b.c").message.contains("no use case"))
  }

  @Test
  func `a use case that breaks the rules says it once for each problem, with the input's name`() {
    let error = UseCaseEditingError.invalidUseCase(
      name: "new.yml",
      problems: ["one", "two"],
    )

    #expect(error.message == "new.yml: one\nnew.yml: two")
  }
}
