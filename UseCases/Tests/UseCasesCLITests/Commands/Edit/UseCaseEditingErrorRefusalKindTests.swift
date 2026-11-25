import Testing
import UseCasesCore
@testable import UseCasesCLI

struct UseCaseEditingErrorRefusalKindTests {
  @Test(arguments: [
    (UseCaseEditingError.unknown(identifier: "a.b.c"), RefusalKind.usage),
    (.noGroup(identifier: "a"), .usage),
    (.invalidUseCase(name: "stdin", problems: ["x"]), .invalid),
    (.wouldNotReadBack(file: "f.yml"), .refused),
  ])
  func `a refusal is told to a script as the kind the design gives it`(
    error: UseCaseEditingError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }
}
