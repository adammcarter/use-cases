import Testing
import UseCasesCore
@testable import UseCasesCLI

struct DocsErrorRefusalKindTests {
  @Test(arguments: [
    (DocsError.search(.changed), RefusalKind.refused),
    (DocsError.guides(.missing("quirks")), .refused),
    (DocsError.guides(.invalid("quirks")), .refused),
    (DocsError.search(.invalidToken), .usage),
    (DocsError.search(.pageSize("0")), .usage),
    (DocsError.search(.words(.noWords)), .usage),
  ])
  func `a changed or unreadable guide is refused and everything else is usage`(
    error: DocsError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }
}
