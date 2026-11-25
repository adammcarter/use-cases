import Testing
@testable import UseCasesCore

struct LayoutRenderingErrorTests {
  @Test(arguments: [
    (LayoutRenderingError.input(message: "x"), UseCaseEditingError.Kind.usage),
    (.invalidIntent(name: "stdin"), .usage),
    (.invalidProposal(name: "stdin", problem: "x"), .usage),
    (.batch(.repeated(identifier: "a.b.c")), .usage),
    (.batch(.editing(.invalidUseCase(name: "stdin", problems: ["x"]))), .invalid),
    (.unknownUseCase(identifier: "a.b.c"), .usage),
    (.notApplied(identifier: "a.b.c"), .refused),
    (.status(.fingerprint("x")), .refused),
  ])
  func `a refusal is told to a script as usage, invalid or refused`(
    error: LayoutRenderingError,
    kind: UseCaseEditingError.Kind,
  ) {
    #expect(error.kind == kind)
  }

  @Test
  func `the messages carry the words the design pins`() {
    #expect(
      LayoutRenderingError.invalidProposal(name: "p.yml", problem: "a proposal has a `title`")
        .message == "p.yml: a proposal has a `title`",
    )
    #expect(
      LayoutRenderingError.invalidIntent(name: "stdin").message
        .contains("an intent has `what` and `why`"),
    )
    #expect(LayoutRenderingError.unknownUseCase(identifier: "a.b.c").message
      .contains("no use case"))
    #expect(
      LayoutRenderingError.notApplied(identifier: "a.b.c").message
        .hasSuffix("apply the proposal before its results"),
    )
    #expect(LayoutRenderingError.batch(.repeated(identifier: "a.b.c")).message
      .contains("at most once"))
    #expect(LayoutRenderingError.status(.storage(problems: ["a", "b"])).message == "a\nb")
    #expect(LayoutRenderingError.input(message: "gone").message == "gone")
  }
}
