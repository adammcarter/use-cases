import Testing
@testable import UseCasesCore

struct UseCaseApprovingErrorTests {
  @Test(arguments: [
    (UseCaseApprovingError.approver(reason: "x"), UseCaseEditingError.Kind.usage),
    (.namedAndAll, .usage),
    (.nothingAsked, .usage),
    (.editing(.unknown(identifier: "a.b.c")), .usage),
    (.editing(.wouldNotReadBack(file: "f.yml")), .refused),
    (.stamping(.unfingerprintable(identifier: "a.b.c", reason: "x")), .refused),
  ])
  func `a refusal is told to a script as usage, invalid or refused`(
    error: UseCaseApprovingError,
    kind: UseCaseEditingError.Kind,
  ) {
    #expect(error.kind == kind)
  }

  @Test
  func `asking for both or neither says not both`() {
    #expect(UseCaseApprovingError.namedAndAll.message.contains("not both"))
    #expect(UseCaseApprovingError.nothingAsked.message.contains("not both"))
  }

  @Test
  func `an unknown use case is said as the other commands say it`() {
    #expect(
      UseCaseApprovingError.editing(.unknown(identifier: "a.b.c")).message
        .contains("no use case 'a.b.c'"),
    )
  }
}
