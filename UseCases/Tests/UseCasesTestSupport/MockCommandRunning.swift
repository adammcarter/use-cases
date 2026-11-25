import UseCasesCore

/// A runner that starts nothing: it records what it is asked to run and answers as the test
/// decides.
public actor MockCommandRunning: CommandRunning {
  /// What it does with each program it is asked to run.
  public enum Behaviour: Sendable {
    /// Ends at once with this outcome.
    case answering(CommandOutcome)

    /// Cannot run the program.
    case failing(CommandRunningError)

    /// Keeps running until the calling task is cancelled, and then ends as cancelled.
    case runningUntilCancelled
  }

  /// Every program it was asked to run, in order.
  public private(set) var invocations: [CommandInvocation] = []

  /// Each program as it starts, so a test can wait for a call to be running without waiting on a
  /// timer.
  public nonisolated let starts: AsyncStream<CommandInvocation>

  /// How each program ended, as it ends, so a test can wait for a cancelled call to have
  /// stopped.
  public nonisolated let endings: AsyncStream<CommandEnding>

  private let continuation: AsyncStream<CommandInvocation>.Continuation
  private let endingContinuation: AsyncStream<CommandEnding>.Continuation
  private let behaviour: Behaviour

  public init(_ behaviour: Behaviour) {
    self.behaviour = behaviour

    let (starts, continuation) = AsyncStream.makeStream(of: CommandInvocation.self)
    self.starts = starts
    self.continuation = continuation

    let (endings, endingContinuation) = AsyncStream.makeStream(of: CommandEnding.self)
    self.endings = endings
    self.endingContinuation = endingContinuation
  }

  /// Ends with `stdout` printed and the exit code given.
  public init(
    printing standardOutput: String,
    standardError: String = "",
    exitCode: Int32 = 0,
  ) {
    self.init(
      .answering(
        CommandOutcome(
          ending: .exited(exitCode),
          standardOutput: standardOutput,
          standardError: standardError,
        ),
      ),
    )
  }

  public func run(
    _ invocation: CommandInvocation,
  ) async throws(CommandRunningError) -> CommandOutcome {
    invocations.append(invocation)
    continuation.yield(invocation)

    switch behaviour {
    case let .answering(outcome):
      return outcome
    case let .failing(error):
      throw error
    case .runningUntilCancelled:
      // Iterating a stream nothing feeds ends only when the task is cancelled.
      var waiting = AsyncStream<Void> { _ in }.makeAsyncIterator()
      _ = await waiting.next()
      endingContinuation.yield(.cancelled)

      return CommandOutcome(
        ending: .cancelled,
        standardOutput: "",
        standardError: "",
      )
    }
  }
}
