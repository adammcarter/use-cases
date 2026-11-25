import Testing
@testable import UseCasesCore

struct VerifyErrorTests {
  @Test(arguments: [
    (VerifyError.noStartedRun, "no started run: run `use-cases verify --start`"),
    (VerifyError.severalStartedRuns(["a", "b"]), "name one with --run-id"),
    (VerifyError.severalOpenRuns(["a", "b"]), "name one with --run-id"),
    (VerifyError.stoppedBeforeFinishing("a"), "stopped before finishing it"),
    (VerifyError.stoppedBeforeFinishing("a"), "use-cases verify --abort --run-id a"),
    (VerifyError.beingFinished("a"), "is being finished by another process"),
    (VerifyError.settingsChanged(run: "a"), "changed for this run's validations since `--start`"),
    (VerifyError.noOpenRun, "no open run"),
    (VerifyError.alreadySealed("a"), "already finished"),
    (VerifyError.noSuchRun("a"), "a"),
    (VerifyError.stagedResults(run: "a"), "--abort --run-id a"),
    (VerifyError.storage("it broke"), "it broke"),
    (VerifyError.invalidWorkspace(problems: ["x", "y"]), "x\ny"),
  ])
  func `the message says what the person needs`(
    error: VerifyError,
    words: String,
  ) {
    #expect(error.message.contains(words))
  }

  @Test
  func `an unknown validation is named with the ones there are`() {
    let message = VerifyError.unknownValidations(
      ["nope"],
      known: ["unit-tests", "style"],
    ).message

    #expect(message.contains("--only names unknown validations: nope"))
    #expect(message.contains("unit-tests, style"))
  }
}
