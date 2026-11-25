import UseCasesCore

/// A cancellation the test decides: never, always, or once something the test can see is true.
public struct MockCancellation: CancellationObserving {
  public static let never = MockCancellation { false }

  public static let always = MockCancellation { true }

  private let isRaised: @Sendable () -> Bool

  /// `isRaised` is asked each time the supervisor looks.
  public init(isRaised: @escaping @Sendable () -> Bool) {
    self.isRaised = isRaised
  }

  public func isCancelled() async -> Bool {
    isRaised()
  }
}
