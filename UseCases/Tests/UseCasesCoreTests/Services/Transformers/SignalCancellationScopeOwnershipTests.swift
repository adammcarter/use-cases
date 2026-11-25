import Testing
@testable import UseCasesCore

/// What the scope asks of the ownership it is given. A double holds no signals, so these touch
/// nothing the process shares and may run beside any other test.
struct SignalCancellationScopeOwnershipTests {
  @Test
  func `scopes that nest take the signals once and give them back once`() async {
    let ownership = SpySignalOwning()
    let scope = SignalCancellationScope(ownership: ownership)

    await scope.begin()
    await scope.begin()
    await scope.end()
    #expect(await ownership.events == ["take"])

    await scope.end()
    #expect(await ownership.events == ["take", "release"])
  }

  @Test
  func `a scope sees a cancellation when the ownership says a signal has come`() async {
    let scope = SignalCancellationScope(ownership: SpySignalOwning(hasSignal: true))

    #expect(await !scope.isCancelled())

    await scope.begin()
    #expect(await scope.isCancelled())
    #expect(await !scope.claimWrite())
  }
}
