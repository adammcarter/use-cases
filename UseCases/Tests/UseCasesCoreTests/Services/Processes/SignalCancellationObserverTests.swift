import Testing
@testable import UseCasesCore

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// These look at what the observer installed, and run the installed handler themselves, rather
/// than raise a real signal. A test process may block a signal on the thread that raises it, and
/// a signal left pending is delivered later, after the observer has gone, and ends the whole
/// test run.
@Suite(.serialized)
struct SignalCancellationObserverTests {
  private typealias Handler = @convention(c) (Int32) -> Void

  /// The handler a signal has now. Reading it means setting the default and putting it back.
  private func handler(for signalNumber: Int32) -> Handler? {
    let current = signal(signalNumber, nil)
    signal(signalNumber, current)

    return current
  }

  private func address(of handler: Handler?) -> Int {
    guard let handler else {
      return 0
    }

    return unsafeBitCast(handler, to: Int.self)
  }

  @Test
  func `nothing is cancelled until a signal arrives`() async {
    let observer = SignalCancellationObserver()
    defer {
      SignalCancellationObserver.stopObserving()
    }

    #expect(await !observer.isCancelled())
  }

  // One after the other: the observer's handlers are the process's, so cases side by side would
  // take them from each other.
  @Test
  func `SIGINT, SIGTERM and SIGHUP run a handler that cancels`() async throws {
    for signalNumber in [SIGINT, SIGTERM, SIGHUP] {
      let observer = SignalCancellationObserver()

      let installed = try #require(handler(for: signalNumber))
      installed(signalNumber)

      #expect(await observer.isCancelled())

      SignalCancellationObserver.stopObserving()
    }
  }

  @Test(arguments: [SIGINT, SIGTERM, SIGHUP])
  func `the first signal gives all three their default action, so a second one stops the core`(
    first: Int32,
  ) async throws {
    let observer = SignalCancellationObserver()
    defer {
      SignalCancellationObserver.stopObserving()
    }

    let installed = try #require(handler(for: first))
    installed(first)

    #expect(await observer.isCancelled())
    #expect(handler(for: SIGINT) == nil)
    #expect(handler(for: SIGTERM) == nil)
    #expect(handler(for: SIGHUP) == nil)
  }

  @Test(arguments: [SIGINT, SIGTERM])
  func `a signal the process was told to ignore is taken over all the same`(
    signalNumber: Int32,
  ) async throws {
    signal(signalNumber, SIG_IGN)
    let observer = SignalCancellationObserver()
    defer {
      SignalCancellationObserver.stopObserving()
    }

    let installed = try #require(handler(for: signalNumber))
    installed(signalNumber)

    #expect(await observer.isCancelled())
  }

  @Test
  func `a closed terminal the process was told to ignore stays ignored, as nohup asks`() {
    signal(SIGHUP, SIG_IGN)
    defer {
      signal(SIGHUP, nil)
    }

    _ = SignalCancellationObserver()
    #expect(address(of: handler(for: SIGHUP)) == 1)

    SignalCancellationObserver.stopObserving()
    #expect(address(of: handler(for: SIGHUP)) == 1)
  }

  @Test(arguments: [SIGWINCH, SIGCHLD, SIGURG])
  func `no other signal is taken over`(signalNumber: Int32) {
    let before = address(of: handler(for: signalNumber))

    _ = SignalCancellationObserver()
    defer {
      SignalCancellationObserver.stopObserving()
    }

    #expect(address(of: handler(for: signalNumber)) == before)
  }

  @Test
  func `stopping gives the three signals their default action and forgets the signal`(
  ) async throws {
    let observer = SignalCancellationObserver()
    let installed = try #require(handler(for: SIGINT))
    installed(SIGINT)

    SignalCancellationObserver.stopObserving()

    #expect(handler(for: SIGINT) == nil)
    #expect(handler(for: SIGTERM) == nil)
    #expect(handler(for: SIGHUP) == nil)
    #expect(await !observer.isCancelled())
  }

  @Test
  func `a later observer still sees a signal that arrived before it`() async throws {
    let first = SignalCancellationObserver()
    let installed = try #require(handler(for: SIGTERM))
    installed(SIGTERM)

    let second = SignalCancellationObserver()
    defer {
      SignalCancellationObserver.stopObserving()
    }

    #expect(await first.isCancelled())
    #expect(await second.isCancelled())
  }

  // MARK: - The scope a links job runs in

  @Test
  func `a scope takes the signals over when it begins and gives them back when it ends`()
    async throws
  {
    let before = address(of: handler(for: SIGINT))
    let scope = SignalCancellationScope()

    await scope.begin()

    let installed = try #require(handler(for: SIGINT))
    installed(SIGINT)

    #expect(await scope.isCancelled())

    await scope.end()

    #expect(await !scope.isCancelled())
    #expect(address(of: handler(for: SIGINT)) == before)
  }

  @Test
  func `a scope that never began takes nothing and gives nothing back`() async {
    let before = address(of: handler(for: SIGTERM))
    let scope = SignalCancellationScope()

    #expect(await !scope.isCancelled())

    await scope.end()

    #expect(address(of: handler(for: SIGTERM)) == before)
  }
}
