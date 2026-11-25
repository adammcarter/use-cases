import Testing
import UseCasesCore
@testable import UseCasesCLI

struct VerifyErrorRefusalKindTests {
  @Test(arguments: [
    (VerifyError.unknownValidations(["x"], known: []), RefusalKind.usage),
    (VerifyError.noStartedRun, RefusalKind.refused),
    (VerifyError.severalStartedRuns([]), RefusalKind.refused),
    (VerifyError.noOpenRun, RefusalKind.refused),
    (VerifyError.severalOpenRuns([]), RefusalKind.refused),
    (VerifyError.noSuchRun("x"), RefusalKind.refused),
    (VerifyError.alreadySealed("x"), RefusalKind.refused),
    (VerifyError.stoppedBeforeFinishing("x"), RefusalKind.refused),
    (VerifyError.beingFinished("x"), RefusalKind.refused),
    (VerifyError.settingsChanged(run: "x"), RefusalKind.refused),
    (VerifyError.stagedResults(run: "x"), RefusalKind.refused),
    (VerifyError.invalidWorkspace(problems: []), RefusalKind.invalid),
    (VerifyError.storage("x"), RefusalKind.storage),
  ])
  func `each refusal is told to a script as its kind`(
    error: VerifyError,
    kind: RefusalKind,
  ) {
    #expect(error.refusalKind == kind)
  }

  @Test
  func `a cancellation is not a refusal`() {
    #expect(VerifyError.cancelled.refusalKind == nil)
  }
}
