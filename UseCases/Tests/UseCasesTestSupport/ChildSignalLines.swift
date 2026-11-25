/// The lines a `ChildSignal` has read and not yet handed on, and the waits for them.
actor ChildSignalLines {
  private struct Waiter {
    let ticket: Int
    let cancellation: CancellationFlag
    let continuation: CheckedContinuation<String?, any Error>
  }

  private var lines: [String] = []
  private var waiters: [Waiter] = []
  private var isFinished = false
  private var nextTicket = 0
  private var unnoticedArrivals = 0
  private var arrivalListeners: [CheckedContinuation<Void, Never>] = []

  func receive(_ received: [String]) {
    lines += received
    handOn()
  }

  func finish() {
    isFinished = true
    handOn()
  }

  /// The next line; nil once the signal is closed and every line read has been handed on. A wait
  /// whose task is cancelled throws `CancellationError` and takes no line.
  func next(cancellation: CancellationFlag) async throws -> String? {
    let ticket = nextTicket
    nextTicket += 1

    return try await withTaskCancellationHandler {
      try await wait(
        ticket: ticket,
        cancellation: cancellation,
      )
    } onCancel: {
      cancellation.raise()

      Task {
        await self.cancel(ticket: ticket)
      }
    }
  }

  func wait(
    ticket: Int,
    cancellation: CancellationFlag,
  ) async throws -> String? {
    // A cancel that reached this actor before the wait did found nothing to end.
    if cancellation.isRaised {
      throw CancellationError()
    }

    return try await withCheckedThrowingContinuation { continuation in
      waiters.append(
        Waiter(
          ticket: ticket,
          cancellation: cancellation,
          continuation: continuation,
        ),
      )

      if arrivalListeners.isEmpty {
        unnoticedArrivals += 1
      } else {
        arrivalListeners.removeFirst().resume()
      }

      handOn()
    }
  }

  /// Returns once a wait has begun that no earlier call has returned for, so a test of a wait
  /// that is cancelled while waiting knows it is waiting.
  func nextWaiter() async {
    if unnoticedArrivals > 0 {
      unnoticedArrivals -= 1

      return
    }

    await withCheckedContinuation { continuation in
      arrivalListeners.append(continuation)
    }
  }

  private func cancel(ticket: Int) {
    guard let index = waiters.firstIndex(where: { $0.ticket == ticket }) else {
      return
    }

    waiters.remove(at: index).continuation.resume(throwing: CancellationError())
  }

  private func handOn() {
    // A wait whose task is cancelled ends here even when its cancel has not reached this actor
    // yet: it throws, and takes neither a line nor the end.
    for waiter in waiters where waiter.cancellation.isRaised {
      waiter.continuation.resume(throwing: CancellationError())
    }

    waiters.removeAll { $0.cancellation.isRaised }

    while !waiters.isEmpty, !lines.isEmpty {
      waiters.removeFirst().continuation.resume(returning: lines.removeFirst())
    }

    if isFinished {
      for waiter in waiters {
        waiter.continuation.resume(returning: nil)
      }

      waiters.removeAll()
    }
  }
}
