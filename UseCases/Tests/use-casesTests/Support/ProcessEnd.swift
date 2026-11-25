import Foundation

/// The end of a program the test started, learnt from its termination handler: a wait for it
/// suspends, holding no thread.
final class ProcessEnd: Sendable {
  private let ended: Task<ProcessTermination, Never>

  /// Listens for `process` to end; called before it is started.
  init(of process: Process) {
    let (ending, continuation) = AsyncStream.makeStream(of: ProcessTermination.self)

    process.terminationHandler = { process in
      continuation.yield(
        ProcessTermination(
          isExit: process.terminationReason == .exit,
          status: process.terminationStatus,
        ),
      )
      continuation.finish()
    }

    // The only reader of the ending, and never cancelled, so no wait of a test can end it early.
    ended = Task {
      for await termination in ending {
        return termination
      }

      // Reached only if the process is let go of without ever ending.
      return ProcessTermination(
        isExit: false,
        status: -1,
      )
    }
  }

  /// Returns once the program has ended, with how it ended.
  func termination() async -> ProcessTermination {
    await ended.value
  }
}
