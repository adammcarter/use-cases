import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The read end of a pipe a program writes to, read as the bytes arrive, in pieces, without ever
/// holding a thread while nothing has arrived.
///
/// Each time the pipe holds something, a readability handler reads all of it, at most `readSize`
/// bytes a read, until the pipe is empty or has reached its end: on Linux the last writer going is
/// reported once, so whatever is still in the pipe must be read in that same call.
///
/// A reader made paused reads nothing until it is resumed, and nothing again once it is paused:
/// while it is paused the pipe fills, and the program's writes wait for it.
final class OutputReader: Sendable {
  /// The pieces in the order the program wrote them, ending at the end of its output.
  let chunks: AsyncStream<[UInt8]>

  private let handle: FileHandle
  private let continuation: AsyncStream<[UInt8]>.Continuation
  private let handler: @Sendable (FileHandle) -> Void

  init(
    _ handle: FileHandle,
    readSize: Int,
    isPaused: Bool = false,
  ) {
    let (chunks, continuation) = AsyncStream.makeStream(of: [UInt8].self)
    let descriptor = handle.fileDescriptor

    // Only this process's read end stops waiting; the program's write end is left as it is.
    _ = fcntl(
      descriptor,
      F_SETFL,
      fcntl(descriptor, F_GETFL) | O_NONBLOCK,
    )

    self.chunks = chunks
    self.handle = handle
    self.continuation = continuation

    handler = { handle in
      let isEnded = Self.drain(
        handle,
        readSize: readSize,
        received: { bytes in
          continuation.yield(bytes)
        },
      )

      if isEnded {
        continuation.finish()
      }
    }

    if !isPaused {
      resume()
    }
  }

  /// Reads whatever arrives from now on, until paused. Resuming a reader that has reached the end
  /// of the output changes nothing: the end is found again and the chunks are already finished.
  func resume() {
    handle.readabilityHandler = handler
  }

  /// Reads nothing more until resumed. A read already under way finishes.
  func pause() {
    handle.readabilityHandler = nil
  }

  /// Stops reading and closes the read end, so that the program's next write finds no reader.
  func stop() throws {
    handle.readabilityHandler = nil
    continuation.finish()
    try handle.close()
  }

  /// Reads all `handle` holds now, and says whether every writer has gone. Never waits: a read
  /// that finds the pipe empty but still held fails with EAGAIN and ends the call.
  private static func drain(
    _ handle: FileHandle,
    readSize: Int,
    received: (_ bytes: [UInt8]) -> Void,
  ) -> Bool {
    var buffer = [UInt8](
      repeating: 0,
      count: readSize,
    )

    while true {
      let count = read(
        handle.fileDescriptor,
        &buffer,
        buffer.count,
      )

      if count > 0 {
        received(Array(buffer[..<count]))
      } else if count < 0, errno == EINTR {
        continue
      } else if count == 0 {
        handle.readabilityHandler = nil

        return true
      } else {
        return false
      }
    }
  }
}
