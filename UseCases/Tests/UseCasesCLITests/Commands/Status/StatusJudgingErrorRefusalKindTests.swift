import Testing
import UseCasesCore
@testable import UseCasesCLI

struct StatusJudgingErrorRefusalKindTests {
  @Test(arguments: [
    (StatusJudgingError.invalidWorkspace(problems: ["a"]), RefusalKind.invalid),
    (StatusJudgingError.storage(problems: ["a"]), RefusalKind.storage),
    (StatusJudgingError.fingerprint("a"), RefusalKind.refused),
  ])
  func `each way of not judging is told to a script by its kind`(
    error: StatusJudgingError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }

  @Test
  func `a refusal puts each problem on a line`() {
    let error = StatusJudgingError.storage(problems: ["a is corrupt", "b is not a run folder"])

    #expect(error.message == "a is corrupt\nb is not a run folder")
  }
}
