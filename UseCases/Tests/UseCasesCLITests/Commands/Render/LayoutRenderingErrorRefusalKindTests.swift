import Testing
import UseCasesCore
@testable import UseCasesCLI

struct LayoutRenderingErrorRefusalKindTests {
  @Test(arguments: [
    (LayoutRenderingError.input(message: "x"), RefusalKind.usage),
    (.invalidIntent(name: "stdin"), .usage),
    (.invalidProposal(name: "stdin", problem: "x"), .usage),
    (.batch(.repeated(identifier: "a.b.c")), .usage),
    (.batch(.editing(.invalidUseCase(name: "stdin", problems: ["x"]))), .invalid),
    (.unknownUseCase(identifier: "a.b.c"), .usage),
    (.notApplied(identifier: "a.b.c"), .refused),
    (.status(.invalidWorkspace(problems: ["x"])), .invalid),
    (.status(.storage(problems: ["x"])), .storage),
    (.status(.fingerprint("x")), .refused),
  ])
  func `a refusal is told to a script as the kind it is`(
    error: LayoutRenderingError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }
}
