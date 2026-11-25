import Testing
@testable import UseCasesCore

struct UseCaseBatchErrorTests {
  @Test(arguments: [
    (UseCaseBatchError.input(message: "x"), UseCaseEditingError.Kind.usage),
    (.notABatch(name: "stdin", problem: nil), .usage),
    (.removeNotIds(name: "stdin"), .usage),
    (.saveNotUseCases(name: "stdin"), .usage),
    (.repeated(identifier: "a.b.c"), .usage),
    (.approver(reason: "x"), .usage),
    (.editing(.unknown(identifier: "a.b.c")), .usage),
    (.editing(.invalidUseCase(name: "stdin", problems: ["x"])), .invalid),
    (.editing(.wouldNotReadBack(file: "f.yml")), .refused),
    (.stamping(.unfingerprintable(identifier: "a.b.c", reason: "x")), .refused),
  ])
  func `a refusal is told to a script as usage, invalid or refused`(
    error: UseCaseBatchError,
    kind: UseCaseEditingError.Kind,
  ) {
    #expect(error.kind == kind)
  }

  @Test
  func `the messages carry the words the design pins`() {
    let notABatch = UseCaseBatchError.notABatch(
      name: "stdin",
      problem: nil,
    )

    #expect(notABatch.message.contains("a batch is a mapping"))
    #expect(
      UseCaseBatchError.removeNotIds(name: "stdin").message.contains("lists use case ids"),
    )
    #expect(
      UseCaseBatchError.repeated(identifier: "a.b.c").message.contains("at most once"),
    )
    #expect(UseCaseBatchError.editing(.unknown(identifier: "a.b.c")).message
      .contains("no use case"))
  }

  @Test
  func `a stranger key is said after what a batch is`() {
    let message = UseCaseBatchError.notABatch(
      name: "batch.yml",
      problem: "'rename' is not a key of a batch",
    ).message

    #expect(message.hasPrefix("batch.yml is not a batch: a batch is a mapping"))
    #expect(message.hasSuffix("; 'rename' is not a key of a batch"))
  }
}
