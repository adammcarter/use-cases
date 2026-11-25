/// Which of two things a test waits for happens first: so a test that waits for an event the
/// code under test should give, beside the end of that code, is told when the code ended without
/// giving it, rather than waiting for ever.
enum EventRace {
  /// Whether `event` returns before `other` does. The wait that loses is left to finish on its
  /// own, and holds no thread meanwhile.
  static func isFirst(
    _ event: @escaping @Sendable () async -> Void,
    before other: @escaping @Sendable () async -> Void,
  ) async -> Bool {
    let (outcomes, outcome) = AsyncStream.makeStream(of: Bool.self)

    Task {
      await event()
      outcome.yield(true)
    }
    Task {
      await other()
      outcome.yield(false)
    }

    var iterator = outcomes.makeAsyncIterator()

    return await iterator.next() ?? false
  }
}
