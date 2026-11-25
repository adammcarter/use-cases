import Foundation
@testable import UseCasesCore

/// Answers each command the test scripted, and remembers what it was asked: by its arguments
/// after the program (as for git), or one step after another in the order they were asked.
actor ScriptedProcessSupervisor: ProcessSupervising {
  /// One scripted command: sees the request, does whatever the test wants to happen while it
  /// runs (writing a report, moving a clock, raising a cancellation), and says how it ended.
  typealias Step = @Sendable (ProcessRequest) async -> Result<ProcessRun, ProcessSupervisingError>

  private let answers: [[String]: Result<ProcessRun, ProcessSupervisingError>]
  private let isInOrder: Bool
  private var steps: [Step]

  /// Every request, in order.
  private(set) var requests: [ProcessRequest] = []

  /// Answers by the arguments after the program.
  init(answers: [[String]: Result<ProcessRun, ProcessSupervisingError>]) {
    self.answers = answers
    isInOrder = false
    steps = []
  }

  /// Answers the first request with the first step, the second with the second, and so on. A
  /// request beyond the last step is a launch failure that says nothing was scripted for it.
  init(inOrder steps: [Step]) {
    answers = [:]
    isInOrder = true
    self.steps = steps
  }

  /// A command that ended by itself with this exit code, having printed `text`.
  static func exited(
    _ code: Int32,
    _ text: String = "",
  ) -> Result<ProcessRun, ProcessSupervisingError> {
    ended(
      .exited(code),
      text,
    )
  }

  /// A command that ended this way, having printed `text`; `wasLaunched` is false only for a
  /// request cancelled before the command started.
  static func ended(
    _ termination: ProcessTermination,
    _ text: String = "",
    wasLaunched: Bool = true,
  ) -> Result<ProcessRun, ProcessSupervisingError> {
    .success(
      ProcessRun(
        termination: termination,
        console: ProcessConsole(
          text: text,
          omittedByteCount: 0,
        ),
        wasLaunched: wasLaunched,
      ),
    )
  }

  /// A step that does nothing but give `answer`.
  static func answering(_ answer: Result<ProcessRun, ProcessSupervisingError>) -> Step {
    { _ in
      answer
    }
  }

  func run(_ request: ProcessRequest) async throws(ProcessSupervisingError) -> ProcessRun {
    requests.append(request)

    if isInOrder {
      guard !steps.isEmpty else {
        throw .couldNotLaunch(reason: "nothing scripted for \(request.arguments)")
      }

      let step = steps.removeFirst()

      return try await step(request).get()
    }

    guard let answer = answers[Array(request.arguments.dropFirst())] else {
      throw .couldNotLaunch(reason: "nothing scripted for \(request.arguments)")
    }

    return try answer.get()
  }
}
