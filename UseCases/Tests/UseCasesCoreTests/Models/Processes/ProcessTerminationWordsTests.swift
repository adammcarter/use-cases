import Testing
@testable import UseCasesCore

struct ProcessTerminationWordsTests {
  @Test(
    arguments: [
      (ProcessTermination.signaled(9), "command terminated abnormally (signal 9)"),
      (ProcessTermination.signaled(15), "command terminated abnormally (signal 15)"),
      (ProcessTermination.timedOut(after: .seconds(1)), "command timed out after 1 seconds"),
      (ProcessTermination.timedOut(after: .seconds(600)), "command timed out after 600 seconds"),
    ],
  )
  func `an abnormal ending reads as the run error the suite pins`(
    termination: ProcessTermination,
    words: String,
  ) {
    #expect(termination.runErrorWords == words)
  }

  @Test(arguments: [ProcessTermination.exited(0), .exited(1), .exited(255), .cancelled])
  func `an exit code or a cancellation is no run error here`(termination: ProcessTermination) {
    #expect(termination.runErrorWords == nil)
  }
}
