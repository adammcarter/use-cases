import UseCasesCore
import UseCasesTestSupport

/// The real observed scope, which tells the test what was done with it, and can hold a claim to
/// write at a gate the test opens: before the claim is made, or after it was granted. A test
/// waits for these instead of for time.
actor WatchedCancellationScope: CancellationScoping {
  private let scope: ObservedCancellationScope
  private let beforeClaiming: UseCasesTestSupport.Gate?
  private let afterClaiming: UseCasesTestSupport.Gate?
  private let outcomes: AsyncStream<Bool>.Continuation

  /// How many times the scope was asked whether a write is going on, which the runner asks only
  /// once it has seen a cancellation.
  private(set) var writingAsks = 0

  /// One element for each claim to write, once it is decided: `true` when it was granted.
  nonisolated let claims: AsyncStream<Bool>

  /// - Parameters:
  ///   - cancellation: What the scope observes.
  ///   - beforeClaiming: A gate each claim waits at before it is made, if any.
  ///   - afterClaiming: A gate each granted claim waits at before it is returned, if any: the
  ///     write has begun, and has not gone on yet.
  init(
    observing cancellation: @escaping @Sendable () -> any CancellationObserving,
    holdingClaimsAt beforeClaiming: UseCasesTestSupport.Gate? = nil,
    holdingWritesAt afterClaiming: UseCasesTestSupport.Gate? = nil,
  ) {
    scope = ObservedCancellationScope(makeObserver: cancellation)
    self.beforeClaiming = beforeClaiming
    self.afterClaiming = afterClaiming

    let (stream, continuation) = AsyncStream.makeStream(of: Bool.self)
    claims = stream
    outcomes = continuation
  }

  /// Waits for the next claim to be decided, and says whether it was granted.
  func nextClaim() async -> Bool? {
    var iterator = claims.makeAsyncIterator()

    return await iterator.next()
  }

  func begin() async {
    await scope.begin()
  }

  func end() async {
    await scope.end()
  }

  func isCancelled() async -> Bool {
    await scope.isCancelled()
  }

  func claimWrite() async -> Bool {
    await beforeClaiming?.wait()

    let claimed = await scope.claimWrite()
    outcomes.yield(claimed)

    if claimed {
      await afterClaiming?.wait()
    }

    return claimed
  }

  func isWriting() async -> Bool {
    writingAsks += 1

    return await scope.isWriting()
  }
}
