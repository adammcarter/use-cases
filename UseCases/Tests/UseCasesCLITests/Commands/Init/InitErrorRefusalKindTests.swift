import Testing
import UseCasesCore
@testable import UseCasesCLI

struct InitErrorRefusalKindTests {
  @Test(arguments: [
    (InitError.invalidPrefix(text: "A", reason: "r"), RefusalKind.usage),
    (InitError.notAFolder(path: "/p"), RefusalKind.refused),
    (InitError.notWorkspaceRoot(path: "/p"), RefusalKind.refused),
    (InitError.insideWorkspace(folder: "/p/q", root: "/p"), RefusalKind.refused),
    (InitError.differentPrefix(existing: nil, asked: "a"), RefusalKind.refused),
    (InitError.invalidWorkspace(problems: ["x"]), RefusalKind.invalid),
    (InitError.obstructed(path: "p", reason: "r"), RefusalKind.refused),
    (InitError.unavailable(message: "m"), RefusalKind.refused),
  ])
  func `each refusal is told to a script with its kind`(
    error: InitError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }
}
