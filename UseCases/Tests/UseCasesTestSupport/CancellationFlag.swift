import Atomics

/// One wait's cancellation, raised the moment its task is cancelled, without waiting for the
/// actor that holds the wait: whatever reaches the actor first, the cancel or the event, finds it
/// raised.
final class CancellationFlag: Sendable {
  private let raised = ManagedAtomic<Bool>(false)

  init() {}

  var isRaised: Bool {
    raised.load(ordering: .acquiring)
  }

  func raise() {
    raised.store(
      true,
      ordering: .releasing,
    )
  }
}
