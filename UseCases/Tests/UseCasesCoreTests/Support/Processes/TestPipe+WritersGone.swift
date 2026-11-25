import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

extension TestPipe {
  /// Returns once every write end of the pipe is closed, in this process and in any other.
  /// Closing this process's own is not always enough on its own: a process being started at that
  /// moment holds a copy of every descriptor until it has started its program. Nothing may be
  /// written to the pipe, and its read end no longer waits once this has been called.
  func writersGone() async {
    let watched = dup(readEnd)
    _ = fcntl(
      watched,
      F_SETFL,
      fcntl(watched, F_GETFL) | O_NONBLOCK,
    )

    let handle = FileHandle(
      fileDescriptor: watched,
      closeOnDealloc: true,
    )

    // Writers already gone are heard here, without waiting for a handler to be told.
    var first: UInt8 = 0

    if read(watched, &first, 1) == 0 {
      return
    }

    let (ending, ended) = AsyncStream.makeStream(of: Void.self)

    // On Linux the last writer going is reported once, so each call reads to the end of the file
    // or until the pipe is empty.
    handle.readabilityHandler = { handle in
      var byte: UInt8 = 0

      while true {
        let count = read(
          handle.fileDescriptor,
          &byte,
          1,
        )

        if count > 0 || (count < 0 && errno == EINTR) {
          continue
        }

        if count == 0 {
          handle.readabilityHandler = nil
          ended.finish()
        }

        return
      }
    }

    for await _ in ending {}

    // Also keeps the handle, and so the descriptor it watches, until the end has been heard.
    handle.readabilityHandler = nil
  }
}
