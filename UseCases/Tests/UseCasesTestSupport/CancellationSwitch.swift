import Atomics
import UseCasesCore

/// A cancellation the test raises when something it can see has happened: from the test itself,
/// or from a synchronous spy hook or double. Once raised it stays raised.
public final class CancellationSwitch: CancellationObserving {
  private let isRaised = ManagedAtomic<Bool>(false)

  public init() {}

  /// Raises the switch. Never waits, so a synchronous hook may call it.
  public func raise() {
    isRaised.store(
      true,
      ordering: .releasing,
    )
  }

  public func isCancelled() async -> Bool {
    isRaised.load(ordering: .acquiring)
  }
}
