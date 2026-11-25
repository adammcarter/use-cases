import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Cancels on SIGINT, SIGTERM and SIGHUP (a closed terminal), and on no other signal (chapter 13
/// §15). Making one takes over the three for the whole process: the handler sets a flag, and the
/// supervisor, which sees the flag, stops the command it is running. The first signal also gives
/// all three their default action back, so that a second one stops the core at once.
struct SignalCancellationObserver: CancellationObserving {
  /// Starts observing the three signals. A signal that arrived before this observer was made is
  /// still seen: a cancellation is not forgotten because someone else started observing later.
  /// Ctrl-C and SIGTERM are taken over even when the process was told to ignore them, as a
  /// background job is: a request that is cancelled is cancelled. A closed terminal the process
  /// was told to ignore, as `nohup` tells it to, stays ignored: that is what `nohup` asks for.
  init() {
    ProcessSignalFlag.prepare()

    for signalNumber in Self.signals {
      let previous = signal(signalNumber, Self.handler)

      if signalNumber == SIGHUP, Self.isIgnore(previous) {
        signal(signalNumber, previous)
      }
    }
  }

  /// The signals that cancel a request.
  static let signals = [SIGINT, SIGTERM, SIGHUP]

  /// Gives the signals back their default action, leaving an ignored closed terminal ignored,
  /// and forgets any signal seen.
  static func stopObserving() {
    for signalNumber in signals {
      let previous = signal(signalNumber, nil)

      if signalNumber == SIGHUP, isIgnore(previous) {
        signal(signalNumber, previous)
      }
    }

    ProcessSignalFlag.clear()
  }

  func isCancelled() async -> Bool {
    ProcessSignalFlag.isRaised
  }

  /// Whether `action` is SIG_IGN, which is the address 1 on Darwin and Linux alike.
  private static func isIgnore(_ action: some Any) -> Bool {
    unsafeBitCast(action, to: Int.self) == 1
  }

  /// Sets the flag and gives the three signals their default action back, which is all the
  /// handler may do: both calls are safe in a handler.
  private static let handler: @convention(c) (Int32) -> Void = { _ in
    ProcessSignalFlag.raise()
    signal(SIGINT, nil)
    signal(SIGTERM, nil)
    signal(SIGHUP, nil)
  }
}
