import Foundation
@testable import UseCasesCore

/// A stopper that stops nothing and remembers whose group it was asked to stop.
actor MockProcessGroupStopper: ProcessGroupStopping {
  private(set) var stopped: [pid_t] = []

  func stop(leader: pid_t) {
    stopped.append(leader)
  }
}
