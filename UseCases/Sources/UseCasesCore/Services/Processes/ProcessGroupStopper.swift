import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Stops a command and everything it started (chapter 14 §11): SIGTERM to the whole group, a
/// wait of up to `grace` for the group to empty, then SIGKILL to what is left.
struct ProcessGroupStopper<ClockType: Clock>: ProcessGroupStopping
  where ClockType.Duration == Duration
{
  let clock: ClockType
  let grace: Duration
  let pollInterval: Duration
  let reaper: any ProcessReaping

  /// The leader is the process the supervisor started and whose ID names the group; it has not
  /// been collected before this call.
  ///
  /// The stop runs as a task of its own, which a cancellation of the caller does not reach: a
  /// cancelled caller still has to leave no process behind.
  func stop(leader: pid_t) async {
    await Task {
      await stopGroup(leader: leader)
    }.value
  }

  private func stopGroup(leader: pid_t) async {
    var isLeaderCollected = false

    killpg(leader, SIGTERM)

    await waitForGroupToEnd(
      leader: leader,
      isLeaderCollected: &isLeaderCollected,
    )

    // Whatever is left ignored SIGTERM, or took too long over it. SIGKILL cannot be ignored,
    // so what the second wait ends on is the system collecting what died. A group that is
    // already gone is left alone: its ID could be in use by something else by now.
    guard !isGroupGone(leader) else {
      return
    }

    killpg(leader, SIGKILL)

    await waitForGroupToEnd(
      leader: leader,
      isLeaderCollected: &isLeaderCollected,
    )
  }

  /// Polls until the group is gone or `grace` has passed. The group counts as gone when
  /// `killpg(group, 0)` finds nobody. A process that has ended but not been collected still
  /// counts as there, so the leader, which is ours to collect, is collected on the way; the
  /// others are collected by the system. A leader that cannot be asked about is taken as
  /// collected: there is nothing more to be done for it.
  private func waitForGroupToEnd(
    leader: pid_t,
    isLeaderCollected: inout Bool,
  ) async {
    let deadline = clock.now.advanced(by: grace)

    while true {
      if !isLeaderCollected {
        do throws(ProcessSupervisingError) {
          isLeaderCollected = try await reaper.poll(leader) != nil
        } catch {
          isLeaderCollected = true
        }
      }

      if isGroupGone(leader) || clock.now >= deadline {
        return
      }

      try? await clock.sleep(for: pollInterval)
    }
  }

  private func isGroupGone(_ group: pid_t) -> Bool {
    killpg(group, 0) != 0 && errno == ESRCH
  }
}
