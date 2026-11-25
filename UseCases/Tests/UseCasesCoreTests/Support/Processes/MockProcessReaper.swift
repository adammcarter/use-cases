import Foundation
@testable import UseCasesCore

/// A reaper that answers from a script, one answer per question, the last one for every question
/// after.
actor MockProcessReaper: ProcessReaping {
  private var answers: [Result<ProcessTermination?, ProcessSupervisingError>]

  init(answers: [Result<ProcessTermination?, ProcessSupervisingError>]) {
    self.answers = answers
  }

  /// Every question is answered: still running.
  static var running: MockProcessReaper {
    MockProcessReaper(answers: [.success(nil)])
  }

  func poll(_ processIdentifier: pid_t) throws(ProcessSupervisingError) -> ProcessTermination? {
    let answer = answers.count > 1 ? answers.removeFirst() : answers[0]

    switch answer {
    case let .success(termination):
      return termination
    case let .failure(error):
      throw error
    }
  }
}
