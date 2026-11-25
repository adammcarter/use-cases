/// The first of several values offered from tasks racing one another; later offers are dropped.
/// A wait for it suspends, holding no thread.
actor FirstToArrive<Value: Sendable> {
  private var first: Value?
  private var waiters: [CheckedContinuation<Value, Never>] = []

  /// Offers `value`, which wins if nothing was offered before it.
  func offer(_ value: Value) {
    guard first == nil else {
      return
    }

    first = value

    for waiter in waiters {
      waiter.resume(returning: value)
    }

    waiters.removeAll()
  }

  /// The value that won, once one has been offered.
  func value() async -> Value {
    if let first {
      return first
    }

    return await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }
}
