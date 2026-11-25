import Foundation

/// The lines a program has written and the test has not taken yet, and the waits for them.
actor WireLines {
  private static let newline = UInt8(ascii: "\n")

  private var pending: [UInt8] = []
  private var searched = 0
  private var isFinished = false
  private var waiters: [CheckedContinuation<Data?, Never>] = []
  private var lineWatchers: [CheckedContinuation<Void, Never>] = []
  private var endWatchers: [CheckedContinuation<Void, Never>] = []

  func receive(_ bytes: [UInt8]) {
    pending += bytes
    handOn()
  }

  /// The output has ended: a last line with no newline is never handed on.
  func finish() {
    isFinished = true
    handOn()
  }

  /// The next line, without its newline; nil once the output has ended and every line has been
  /// taken.
  func next() async -> Data? {
    if waiters.isEmpty, let line = takeLine() {
      return line
    }

    if isFinished {
      return nil
    }

    return await withCheckedContinuation { continuation in
      waiters.append(continuation)
    }
  }

  /// A line that is already here, taken; nil if none is, without waiting.
  func takeReady() -> Data? {
    waiters.isEmpty ? takeLine() : nil
  }

  /// Returns once a line is here to be taken, or the output has ended, and takes nothing.
  func lineOrEnd() async {
    if hasLine() || isFinished {
      return
    }

    await withCheckedContinuation { continuation in
      lineWatchers.append(continuation)
    }
  }

  /// Returns once the output has ended, and takes nothing.
  func end() async {
    if isFinished {
      return
    }

    await withCheckedContinuation { continuation in
      endWatchers.append(continuation)
    }
  }

  private func handOn() {
    while !waiters.isEmpty, let line = takeLine() {
      waiters.removeFirst().resume(returning: line)
    }

    if isFinished {
      for waiter in waiters {
        waiter.resume(returning: nil)
      }

      waiters.removeAll()

      for watcher in endWatchers {
        watcher.resume()
      }

      endWatchers.removeAll()
    }

    if hasLine() || isFinished {
      for watcher in lineWatchers {
        watcher.resume()
      }

      lineWatchers.removeAll()
    }
  }

  private func hasLine() -> Bool {
    guard pending[searched...].contains(Self.newline) else {
      searched = pending.count

      return false
    }

    return true
  }

  private func takeLine() -> Data? {
    guard let end = pending[searched...].firstIndex(of: Self.newline) else {
      searched = pending.count

      return nil
    }

    let line = Data(pending[..<end])
    pending.removeSubrange(...end)
    searched = 0

    return line
  }
}
