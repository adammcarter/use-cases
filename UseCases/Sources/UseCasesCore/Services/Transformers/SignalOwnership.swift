/// Who holds SIGINT and SIGTERM. The signals belong to the process, so scopes that nest, the whole
/// request and the transformer job inside it, share them: the first to begin takes them over, and
/// the last to end gives them back. A scope that ended inside another therefore never lets the
/// default action, which kills the process, fall between two parts of one request.
///
/// A program that started this one with a lifeline (``ProcessLifeline``) cancels it as a signal
/// does, by dying.
actor SignalOwnership: SignalOwning {
  static let shared = SignalOwnership()

  private let inheritedLifeline: @Sendable () -> ProcessLifeline?
  private var lifeline: ProcessLifeline?
  private var holders = 0

  /// - Parameter inheritedLifeline: The lifeline the process was started with, asked for when the
  ///   signals are taken over.
  init(inheritedLifeline: @escaping @Sendable ()
    -> ProcessLifeline? = { ProcessLifeline.inherited })
  {
    self.inheritedLifeline = inheritedLifeline
  }

  /// Whether a signal has been seen since the signals were taken over, or the program that
  /// started this one has died: either cancels.
  var isCancelled: Bool {
    holders > 0 && (ProcessSignalFlag.isRaised || lifeline?.isBroken == true)
  }

  /// One more holder. The first one takes the signals over.
  func take() {
    if holders == 0 {
      _ = SignalCancellationObserver()
      lifeline = inheritedLifeline()
    }

    holders += 1
  }

  /// One holder fewer. The last one gives the signals back and forgets any it saw.
  func release() {
    guard holders > 0 else {
      return
    }

    holders -= 1

    if holders == 0 {
      SignalCancellationObserver.stopObserving()
      lifeline = nil
    }
  }
}
