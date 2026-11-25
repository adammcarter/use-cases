import Testing
@testable import UseCasesCore

struct ProcessSupervisingErrorTests {
  @Test
  func `a command that cannot be launched reads as the run error the suite pins`() {
    let error = ProcessSupervisingError.couldNotLaunch(reason: "No such file or directory")

    #expect(error.description == "command could not be launched: No such file or directory")
  }
}
