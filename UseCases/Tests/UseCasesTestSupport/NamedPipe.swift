import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// The system calls the signals and holds make on a named pipe in a test's folder.
enum NamedPipe {
  static func make(at url: URL) throws(NamedPipeFailure) {
    guard mkfifo(url.path, 0o600) == 0 else {
      throw failure(
        "mkfifo",
        url,
      )
    }
  }

  static func descriptor(
    opening url: URL,
    flags: Int32,
  ) throws(NamedPipeFailure) -> Int32 {
    let descriptor = open(url.path, flags)

    guard descriptor >= 0 else {
      throw failure(
        "open",
        url,
      )
    }

    return descriptor
  }

  static func release(_ descriptor: Int32) {
    close(descriptor)
  }

  /// Takes the path away, so a child that opens it later never finds the pipe.
  static func remove(_ url: URL) {
    unlink(url.path)
  }

  /// Reads all that `handle`, opened not to wait, holds now, handing each piece to `received`,
  /// and says whether every writer has gone. Called from a readability handler: on Linux the
  /// last writer going is reported once, in what is then the last call, so whatever is still in
  /// the pipe must be read in that call to reach the end of the file. This loop never waits: a
  /// read that finds the pipe empty but still held fails with EAGAIN and ends the call.
  @discardableResult
  static func drain(
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

  /// The path as one shell word, whatever characters it holds.
  static func shellWord(_ url: URL) -> String {
    "'" + url.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  private static func failure(
    _ call: String,
    _ url: URL,
  ) -> NamedPipeFailure {
    NamedPipeFailure(
      call: call,
      path: url.path,
      errorNumber: errno,
    )
  }
}
