import Atomics
import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A named pipe a child process writes lines to, which reach the test as an event each.
///
/// The test's own end is opened before any child exists, without waiting for a writer, so a child
/// that opens the pipe to write never waits for the test. The signal also holds a write end of
/// its own, so one child closing the pipe never ends the lines for the next.
public final class ChildSignal: Sendable {
  /// The most a single read takes, so a longer line arrives in pieces.
  static let readSize = 4096

  public let url: URL

  private let readEnd: FileHandle
  private let ownWriteEnd: Int32
  private let chunks: AsyncStream<[UInt8]>.Continuation
  private let lines = ChildSignalLines()
  private let isClosed = ManagedAtomic<Bool>(false)

  /// Makes the named pipe at `url`, which must not exist yet, and starts listening on it.
  public init(at url: URL) throws(NamedPipeFailure) {
    try NamedPipe.make(at: url)

    let readDescriptor = try NamedPipe.descriptor(
      opening: url,
      flags: O_RDONLY | O_NONBLOCK | O_CLOEXEC,
    )
    let writeDescriptor: Int32

    do {
      writeDescriptor = try NamedPipe.descriptor(
        opening: url,
        flags: O_WRONLY | O_CLOEXEC,
      )
    } catch {
      NamedPipe.release(readDescriptor)

      throw error
    }

    let (chunkStream, chunks) = AsyncStream.makeStream(of: [UInt8].self)
    let lines = lines

    self.url = url
    self.chunks = chunks
    ownWriteEnd = writeDescriptor
    readEnd = FileHandle(
      fileDescriptor: readDescriptor,
      closeOnDealloc: true,
    )

    // The only reader of the chunks, and never cancelled, so no wait of a test can end them.
    Task {
      var splitter = LineSplitter()

      for await chunk in chunkStream {
        await lines.receive(splitter.lines(completedBy: chunk))
      }

      await lines.finish()
    }

    readEnd.readabilityHandler = { handle in
      NamedPipe.drain(
        handle,
        readSize: Self.readSize,
        received: { bytes in
          chunks.yield(bytes)
        },
      )
    }
  }

  deinit {
    close()
  }

  /// The shell text that writes `value` as one line to this signal. `value` is left for the
  /// shell to expand, so `$$` is the writing shell's process ID.
  public func shellText(saying value: String) -> String {
    "echo \(value) > \(NamedPipe.shellWord(url))"
  }

  /// The next line written, without its newline, in the order written; nil once the signal is
  /// closed and every line already read has been handed on. A wait whose task is cancelled
  /// throws `CancellationError` and leaves the line for the next wait.
  public func next() async throws -> String? {
    try await lines.next(cancellation: CancellationFlag())
  }

  /// Stops listening. The path goes first, so a child that writes later makes a plain file there
  /// and never waits on a pipe nobody reads.
  public func close() {
    guard !isClosed.exchange(true, ordering: .acquiringAndReleasing) else {
      return
    }

    NamedPipe.remove(url)
    readEnd.readabilityHandler = nil
    NamedPipe.release(ownWriteEnd)
    chunks.finish()
  }
}
