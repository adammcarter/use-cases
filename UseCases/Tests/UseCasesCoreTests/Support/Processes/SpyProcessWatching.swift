import Foundation
@testable import UseCasesCore

/// A watcher that notes what it is asked to watch, and answers as told: with an ending of its
/// own, or the ending that another watcher finds.
actor SpyProcessWatching: ProcessWatching {
  /// One command watched.
  struct Watch: Equatable {
    let leader: pid_t
    let timeout: Duration?
  }

  /// Every command watched, in order.
  private(set) var watches: [Watch] = []

  private let isRaised: Bool
  private let watching: @Sendable (pid_t, Duration?) async throws(ProcessSupervisingError)
    -> ProcessTermination

  /// A watcher that sees every command end as `termination`, and says the run was cancelled if
  /// `isCancelled`.
  init(
    ending termination: ProcessTermination = .exited(0),
    isCancelled: Bool = false,
  ) {
    isRaised = isCancelled
    watching = { _, _ async throws(ProcessSupervisingError) -> ProcessTermination in
      termination
    }
  }

  /// A watcher that notes each command and leaves its watching to `watcher`.
  init(watchingThrough watcher: any ProcessWatching) {
    isRaised = false
    watching = { leader, timeout async throws(ProcessSupervisingError) -> ProcessTermination in
      try await watcher.watch(
        leader: leader,
        timeout: timeout,
      )
    }
  }

  func watch(
    leader: pid_t,
    timeout: Duration?,
  ) async throws(ProcessSupervisingError) -> ProcessTermination {
    watches.append(
      Watch(
        leader: leader,
        timeout: timeout,
      ),
    )

    return try await watching(leader, timeout)
  }

  func isCancelled() async -> Bool {
    isRaised
  }
}
