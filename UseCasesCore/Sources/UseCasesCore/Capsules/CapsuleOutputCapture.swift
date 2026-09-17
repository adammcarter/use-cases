import Foundation

/// The bytes a capsule command wrote, and why reading them stopped: node's
/// `SyncProcessRunner` loop over a child's stdout and stderr.
///
/// One thread, no concurrency: both streams are read in a `poll(2)` loop whose
/// wait is bounded by the deadline, so neither can fill and block the child
/// while the other is being waited on.
struct CapsuleOutputCapture {
  enum Ending {
    case finished
    case timedOut
    case overflowed
  }

  /// node's `maxBuffer` for the runner, shared by both streams.
  static let maximumBufferBytes = 1_048_576
  /// libuv reads at most this much at a time.
  static let readChunkBytes = 65536

  let descriptors: [Int32]
  let deadline: ContinuousClock.Instant
  var buffers: [[UInt8]] = [[], []]

  /// Read both streams until both close, the deadline passes, or the bytes
  /// read exceed the buffer.
  mutating func drain() -> Ending {
    var isOpen = [true, true]
    var chunk = [UInt8](repeating: 0, count: Self.readChunkBytes)
    while isOpen.contains(true) {
      guard let wait = remainingMilliseconds() else {
        return .timedOut
      }
      var polled = descriptors.indices.filter { isOpen[$0] }.map { index in
        pollfd(fd: descriptors[index], events: Int16(POLLIN), revents: 0)
      }
      guard poll(&polled, nfds_t(polled.count), wait) > 0 else {
        continue
      }
      for entry in polled where entry.revents != 0 {
        guard let index = descriptors.firstIndex(of: entry.fd) else {
          continue
        }
        let count = read(entry.fd, &chunk, chunk.count)
        if count > 0 {
          buffers[index] += chunk[0 ..< count]
          if buffers[0].count + buffers[1].count > Self.maximumBufferBytes {
            return .overflowed
          }
        } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
          isOpen[index] = false
        }
      }
    }
    return .finished
  }

  /// The child's wait status once it is reaped. While a kill is still pending
  /// — both streams closed, the child still running — the deadline still
  /// applies: past it the child gets SIGTERM.
  func waitForExit(
    _ processIdentifier: pid_t,
    isKillPending: Bool,
  ) -> Int32 {
    var status: Int32 = 0
    while isKillPending {
      let reaped = waitpid(processIdentifier, &status, WNOHANG)
      if reaped == processIdentifier || (reaped < 0 && errno != EINTR) {
        return status
      }
      guard let wait = remainingMilliseconds() else {
        kill(processIdentifier, SIGTERM)
        break
      }
      var none = pollfd()
      _ = poll(&none, 0, min(wait, 5))
    }
    while waitpid(processIdentifier, &status, 0) < 0, errno == EINTR {}
    return status
  }

  /// Milliseconds until the deadline, rounded up; nil once it has passed.
  private func remainingMilliseconds() -> Int32? {
    let remaining = deadline - ContinuousClock.now
    guard remaining > .zero else {
      return nil
    }
    let (seconds, attoseconds) = remaining.components
    let milliseconds = seconds * 1000 + (attoseconds + 999_999_999_999_999) / 1_000_000_000_000_000
    return Int32(clamping: max(1, milliseconds))
  }
}
