import Foundation

/// Watches one started command until it ends, its time is up, or a cancellation arrives
/// (chapter 14 §11, §14). Waiting is a polling loop on the injected clock, so nothing blocks a
/// thread of the concurrency pool.
struct ProcessWatcher<ClockType: Clock>: ProcessWatching
  where ClockType.Duration == Duration
{
  let cancellation: any CancellationObserving
  let clock: ClockType
  let pollInterval: Duration
  let reaper: any ProcessReaping
  let stopper: any ProcessGroupStopping

  /// Watches the command until it ends, its time is up (counted from now, the launch having
  /// succeeded; `nil` means it has no limit), or a cancellation arrives; the last two stop its
  /// whole group, and so does a failure to ask about the command, since it is running still.
  func watch(
    leader: pid_t,
    timeout: Duration?,
  ) async throws(ProcessSupervisingError) -> ProcessTermination {
    let deadline = timeout.map { limit in
      clock.now.advanced(by: limit)
    }

    while true {
      if let ended = try await poll(leader) {
        return ended
      }

      if await isCancelled() {
        await stopper.stop(leader: leader)

        return .cancelled
      }

      if let deadline, let timeout, clock.now >= deadline {
        // A command that ended since the last look ended in time, whatever the clock says now.
        if let ended = try await poll(leader) {
          return ended
        }

        await stopper.stop(leader: leader)

        return .timedOut(after: timeout)
      }

      do {
        try await clock.sleep(for: pollInterval)
      } catch {
        // The task was cancelled while the command ran.
        await stopper.stop(leader: leader)

        return .cancelled
      }
    }
  }

  /// Asks whether the command has ended. A command that cannot be asked about is still running,
  /// so its group is stopped before the failure is passed on.
  private func poll(_ leader: pid_t) async throws(ProcessSupervisingError) -> ProcessTermination? {
    do throws(ProcessSupervisingError) {
      return try await reaper.poll(leader)
    } catch {
      await stopper.stop(leader: leader)

      throw error
    }
  }

  /// Whether the run was cancelled: its task, or the observer.
  func isCancelled() async -> Bool {
    if Task.isCancelled {
      return true
    }

    return await cancellation.isCancelled()
  }
}
