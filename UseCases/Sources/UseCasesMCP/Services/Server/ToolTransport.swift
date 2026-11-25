import Foundation
import Logging
import MCP

/// The transport the server speaks through: the host's own, made fit for tools.
///
/// What goes out goes one frame at a time, to its end (see ``FrameWriter``). What comes in has the
/// arguments of each call set aside exactly as written (see ``ToolCallArguments``). And a frame
/// that cannot be written, because the host has gone, ends what comes in, so that the server ends
/// and stops the calls still running instead of answering nobody.
actor ToolTransport: Transport {
  nonisolated let logger: Logger

  private let transport: any Transport
  private let writer: any FrameWriting
  private let reader: any ToolFrameReading
  private let incoming: AsyncThrowingStream<Data, any Error>
  private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
  private var pump: Task<Void, Never>?

  /// - Parameters:
  ///   - transport: The host's transport.
  ///   - logger: The host transport's logger.
  ///   - arguments: Where the arguments of the calls are kept.
  init(
    transport: any Transport,
    logger: Logger,
    arguments: any ToolCallArgumentHolding,
  ) {
    self.init(
      transport: transport,
      logger: logger,
      writer: FrameWriter(transport: transport),
      reader: ToolFrameReader(arguments: arguments),
    )
  }

  /// - Parameters:
  ///   - transport: The host's transport.
  ///   - logger: The host transport's logger.
  ///   - writer: Writes the frames that go out to the host.
  ///   - reader: Reads the frames that come in from the host.
  init(
    transport: any Transport,
    logger: Logger,
    writer: any FrameWriting,
    reader: any ToolFrameReading,
  ) {
    self.transport = transport
    self.logger = logger
    self.writer = writer
    self.reader = reader

    let (incoming, continuation) = AsyncThrowingStream.makeStream(of: Data.self)
    self.incoming = incoming
    self.continuation = continuation
  }

  func connect() async throws {
    try await transport.connect()

    guard pump == nil else {
      return
    }

    let transport = transport
    let reader = reader
    let continuation = continuation
    pump = Task {
      do {
        for try await frame in await transport.receive() {
          let read = await reader.frame(for: frame)
          continuation.yield(read)
        }

        continuation.finish()
      } catch {
        continuation.finish(throwing: error)
      }
    }
  }

  func disconnect() async {
    pump?.cancel()
    pump = nil
    continuation.finish()
    await transport.disconnect()
  }

  func send(_ data: Data) async throws {
    do {
      try await writer.write(data)
    } catch {
      continuation.finish()

      throw error
    }
  }

  func receive() -> AsyncThrowingStream<Data, any Error> {
    incoming
  }
}
