import Foundation
import UseCasesTestSupport
@testable import UseCasesCore

/// The system's reaper, which also tells the test when it was first asked about a command and
/// when it first found one ended. The watcher and the stopper each read the clock for their limit
/// before they first ask, so a test that has heard `asked` knows the limit is set from then on.
struct ObservedProcessReaper: ProcessReaping {
  /// Opened the first time the reaper is asked.
  let asked = UseCasesTestSupport.Gate()

  /// Opened the first time the reaper finds a command ended.
  let collected = UseCasesTestSupport.Gate()

  private let reaper = ProcessReaper()

  func poll(_ processIdentifier: pid_t) async throws(ProcessSupervisingError)
    -> ProcessTermination?
  {
    await asked.open()

    let termination = try await reaper.poll(processIdentifier)

    if termination != nil {
      await collected.open()
    }

    return termination
  }
}
