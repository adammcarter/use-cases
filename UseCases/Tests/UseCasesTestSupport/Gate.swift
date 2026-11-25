/// A gate the test opens once. A task that waits on it suspends until then, holding no thread;
/// a task that waits after it was opened goes straight through.
public actor Gate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var unnoticedArrivals = 0
  private var listeners: [CheckedContinuation<Void, Never>] = []

  public init() {}

  /// Opens the gate and lets every waiting task through. Opening it again changes nothing.
  public func open() {
    isOpen = true

    for waiter in waiters {
      waiter.resume()
    }

    waiters.removeAll()
  }

  /// Returns once the gate is open.
  public func wait() async {
    if isOpen {
      return
    }

    await withCheckedContinuation { continuation in
      waiters.append(continuation)

      if listeners.isEmpty {
        unnoticedArrivals += 1
      } else {
        listeners.removeFirst().resume()
      }
    }
  }

  /// Returns once a task has begun waiting at the closed gate that no earlier call has returned
  /// for. A task that found the gate open never waited, so it is not counted.
  public func nextWaiter() async {
    if unnoticedArrivals > 0 {
      unnoticedArrivals -= 1

      return
    }

    await withCheckedContinuation { continuation in
      listeners.append(continuation)
    }
  }
}
