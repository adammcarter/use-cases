import Testing
import UseCasesCore
@testable import UseCasesCLI

struct WorkspaceLoadingErrorRefusalKindTests {
  @Test(arguments: [
    (WorkspaceLoadingError.noWorkspace(message: "m"), RefusalKind.invalid),
    (WorkspaceLoadingError.invalid(problems: ["a.yml: m"]), RefusalKind.invalid),
    (WorkspaceLoadingError.schemasUnavailable(message: "m"), RefusalKind.refused),
  ])
  func `each way a load fails is told to a script under its kind`(
    error: WorkspaceLoadingError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }
}
