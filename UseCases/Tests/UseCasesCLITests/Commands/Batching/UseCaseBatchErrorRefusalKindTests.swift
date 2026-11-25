import Testing
import UseCasesCore
@testable import UseCasesCLI

struct UseCaseBatchErrorRefusalKindTests {
  @Test(arguments: [
    (UseCaseBatchError.notABatch(name: "stdin", problem: nil), RefusalKind.usage),
    (.repeated(identifier: "a.b.c"), .usage),
    (.editing(.invalidUseCase(name: "stdin", problems: ["x"])), .invalid),
    (.editing(.wouldNotReadBack(file: "f.yml")), .refused),
  ])
  func `a refusal of a batch is told to a script as the kind the design gives it`(
    error: UseCaseBatchError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }

  @Test(arguments: [
    (UseCaseApprovingError.namedAndAll, RefusalKind.usage),
    (.nothingAsked, .usage),
    (.approver(reason: "x"), .usage),
    (.editing(.unknown(identifier: "a.b.c")), .usage),
    (.stamping(.unfingerprintable(identifier: "a.b.c", reason: "x")), .refused),
  ])
  func `a refusal of a sign-off is told to a script as the kind the design gives it`(
    error: UseCaseApprovingError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }

  @Test(arguments: [
    (UseCaseEditingError.Kind.usage, RefusalKind.usage),
    (.invalid, .invalid),
    (.refused, .refused),
  ])
  func `each kind of editing refusal has its kind in a document`(
    editing: UseCaseEditingError.Kind,
    kind: RefusalKind,
  ) {
    #expect(editing.refusalKind == kind)
  }
}
