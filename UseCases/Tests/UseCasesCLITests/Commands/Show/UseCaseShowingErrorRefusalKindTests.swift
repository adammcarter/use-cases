import Testing
import UseCasesCore
@testable import UseCasesCLI

struct UseCaseShowingErrorRefusalKindTests {
  @Test(arguments: [
    (UseCaseShowingError.unknown(identifier: "a.b.c"), RefusalKind.usage),
    (.unfingerprintable(identifier: "a.b.c", reason: "x"), RefusalKind.refused),
  ])
  func `each way of not showing is told to a script by its kind`(
    error: UseCaseShowingError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }
}
