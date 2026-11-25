import Testing
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// Scopes share the process's signals, so these run with the observer's tests, one at a time.
extension SignalCancellationObserverTests {
  /// Whether SIGINT and SIGTERM have their default action. Reading it means setting it and putting
  /// it back.
  private func signalsHaveDefaultAction() -> Bool {
    let interrupt = signal(SIGINT, nil)
    let terminate = signal(SIGTERM, nil)
    signal(SIGINT, interrupt)
    signal(SIGTERM, terminate)

    return interrupt == nil && terminate == nil
  }

  @Test
  func `a scope that has not begun holds nothing and sees nothing`() async {
    let scope = SignalCancellationScope()

    ProcessSignalFlag.raise()
    defer {
      ProcessSignalFlag.clear()
    }

    #expect(await !scope.isCancelled())
    #expect(signalsHaveDefaultAction())
  }

  @Test
  func `a scope that began sees a signal, and gives the signals back when it ends`() async {
    let scope = SignalCancellationScope()

    await scope.begin()
    #expect(await !scope.isCancelled())
    #expect(!signalsHaveDefaultAction())

    ProcessSignalFlag.raise()
    #expect(await scope.isCancelled())

    await scope.end()
    #expect(signalsHaveDefaultAction())
    #expect(await !scope.isCancelled())
  }

  @Test
  func `a scope inside another leaves the signals to it when it ends`() async {
    let outer = SignalCancellationScope()
    let inner = SignalCancellationScope()

    await outer.begin()
    await inner.begin()
    await inner.end()

    #expect(!signalsHaveDefaultAction())

    ProcessSignalFlag.raise()
    #expect(await outer.isCancelled())
    #expect(await !inner.isCancelled())

    await outer.end()
    #expect(signalsHaveDefaultAction())
  }

  @Test
  func `a signal the outer scope has seen is still seen by a scope that begins after it`() async {
    let outer = SignalCancellationScope()
    let later = SignalCancellationScope()

    await outer.begin()
    ProcessSignalFlag.raise()
    await later.begin()

    #expect(await later.isCancelled())

    await later.end()
    await outer.end()
    #expect(await !outer.isCancelled())
  }

  @Test
  func `the last scope to end forgets the signal, so the next request starts clean`() async {
    let first = SignalCancellationScope()
    await first.begin()
    ProcessSignalFlag.raise()
    await first.end()

    let second = SignalCancellationScope()
    await second.begin()

    #expect(await !second.isCancelled())

    await second.end()
  }

  @Test
  func `beginning twice or ending twice holds the signals once`() async {
    let scope = SignalCancellationScope()
    let other = SignalCancellationScope()

    await other.begin()
    await scope.begin()
    await scope.begin()
    await scope.end()
    await scope.end()

    #expect(!signalsHaveDefaultAction())

    await other.end()
    #expect(signalsHaveDefaultAction())
  }

  @Test
  func `a write is claimed while nothing was signalled, and then the scope is writing`() async {
    let scope = SignalCancellationScope()
    await scope.begin()

    #expect(await !scope.isWriting())
    #expect(await scope.claimWrite())
    #expect(await scope.isWriting())

    await scope.end()
    #expect(await !scope.isWriting())
  }

  @Test
  func `a write is refused, and not claimed, once a signal has come`() async {
    let scope = SignalCancellationScope()
    await scope.begin()
    ProcessSignalFlag.raise()

    #expect(await !scope.claimWrite())
    #expect(await !scope.isWriting())

    await scope.end()
  }

  @Test
  func `a signal that comes after the claim does not take the write back`() async {
    let scope = SignalCancellationScope()
    await scope.begin()

    #expect(await scope.claimWrite())

    ProcessSignalFlag.raise()

    #expect(await scope.isCancelled())
    #expect(await scope.isWriting())

    await scope.end()
  }

  @Test
  func `work answered as cancelled and left running cannot write after the signals are given back`()
    async
  {
    let scope = SignalCancellationScope()
    await scope.begin()
    ProcessSignalFlag.raise()

    #expect(await scope.isCancelled())

    await scope.end()

    #expect(await !scope.claimWrite())
  }

  @Test
  func `one scope held twice keeps the signals until it ends twice`() async {
    let scope = SignalCancellationScope()
    await scope.begin()
    await scope.begin()
    await scope.end()

    ProcessSignalFlag.raise()
    #expect(await scope.isCancelled())
    #expect(!signalsHaveDefaultAction())

    await scope.end()
    #expect(signalsHaveDefaultAction())
  }
}
