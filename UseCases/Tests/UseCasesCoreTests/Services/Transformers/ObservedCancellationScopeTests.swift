import Foundation
import Testing
import UseCasesTestSupport
@testable import UseCasesCore

struct ObservedCancellationScopeTests {
  private func scope(cancelled cancellation: some CancellationObserving)
    -> ObservedCancellationScope
  {
    ObservedCancellationScope {
      cancellation
    }
  }

  @Test
  func `it sees nothing until it begins`() async {
    let scope = ObservedCancellationScope { MockCancellation.always }

    #expect(await !scope.isCancelled())

    await scope.begin()

    #expect(await scope.isCancelled())
  }

  @Test
  func `scopes nest: it observes until the last end`() async {
    let scope = ObservedCancellationScope { MockCancellation.always }

    await scope.begin()
    await scope.begin()
    await scope.end()

    #expect(await scope.isCancelled())

    await scope.end()

    #expect(await !scope.isCancelled())
  }

  @Test
  func `a write is claimed while nothing is cancelled, and then it is writing`() async {
    let scope = ObservedCancellationScope { MockCancellation.never }
    await scope.begin()

    #expect(await !scope.isWriting())
    #expect(await scope.claimWrite())
    #expect(await scope.isWriting())

    await scope.end()
    #expect(await !scope.isWriting())
  }

  @Test
  func `a write is refused and not claimed once the request is cancelled`() async {
    let scope = ObservedCancellationScope { MockCancellation.always }
    await scope.begin()

    #expect(await !scope.claimWrite())
    #expect(await !scope.isWriting())
  }

  @Test
  func `a cancellation after the claim does not take the write back`() async {
    let cancellation = CancellationSwitch()
    let scope = scope(cancelled: cancellation)
    await scope.begin()

    #expect(await scope.claimWrite())

    cancellation.raise()

    #expect(await scope.isCancelled())
    #expect(await scope.isWriting())
  }

  @Test
  func `work seen cancelled and left running claims nothing, even after the scope ends`()
    async
  {
    let cancellation = LiftedCancellation(
      raised: CancellationSwitch(),
      lifted: CancellationSwitch(),
    )
    let scope = scope(cancelled: cancellation)
    await scope.begin()
    cancellation.raised.raise()

    #expect(await scope.isCancelled())

    await scope.end()
    cancellation.lifted.raise()

    #expect(await !cancellation.isCancelled())

    await scope.begin()

    #expect(await !scope.claimWrite())
  }
}
