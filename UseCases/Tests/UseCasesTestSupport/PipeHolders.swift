import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// An anonymous pipe given to a child as its standard output, which tells the test when every
/// process holding it has gone: the child, and anything it started that kept the pipe.
///
/// The end of the file on such a pipe is an event on every system, where a named pipe's is not.
public final class PipeHolders: Sendable {
  /// The most a single read takes.
  static let readSize = 65536

  private let readEnd: FileHandle
  private let writeEnd: FileHandle
  private let gone: Task<Void, Never>

  public init() {
    let pipe = Pipe()
    let (ending, ended) = AsyncStream.makeStream(of: Void.self)

    readEnd = pipe.fileHandleForReading
    writeEnd = pipe.fileHandleForWriting

    // The only reader of the ending, and never cancelled, so no wait of a test can end it early.
    gone = Task {
      for await _ in ending {}
    }

    // Only this process's read end stops waiting; the holders' write end is left as it is.
    let readDescriptor = readEnd.fileDescriptor
    _ = fcntl(
      readDescriptor,
      F_SETFL,
      fcntl(readDescriptor, F_GETFL) | O_NONBLOCK,
    )

    // What the holders write is read and dropped, so no holder ever waits to write. Each call
    // empties the pipe, because on Linux the last holder going is reported only once.
    readEnd.readabilityHandler = { handle in
      let isEnded = NamedPipe.drain(
        handle,
        readSize: Self.readSize,
        received: { _ in },
      )

      if isEnded {
        ended.finish()
      }
    }
  }

  /// Starts `process` with the pipe as its standard output, then closes this process's own
  /// write end, so only the child and what it starts hold the pipe. One child per pipe.
  public func run(_ process: Process) throws {
    try handWriteEnd { _ in
      process.standardOutput = writeEnd
      try process.run()
    }
  }

  /// Hands the pipe's write end to `start`, which gives it to the child it starts by whatever
  /// launcher it uses, then closes this process's own write end, as `run(_:)` does.
  @discardableResult
  public func handWriteEnd<Started>(
    to start: (_ writeDescriptor: Int32) throws -> Started,
  ) rethrows -> Started {
    defer {
      try? writeEnd.close()
    }

    return try start(writeEnd.fileDescriptor)
  }

  /// Returns once every process holding the pipe has closed it or ended. A wait whose task is
  /// cancelled goes on waiting: it is never told the holders have gone before they have.
  public func allGone() async {
    await gone.value
  }
}
