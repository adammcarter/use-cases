import Foundation
import MCP
import Testing
@testable import UseCasesMCP

/// What the transport asks of the writer and the reader it is given.
struct ToolTransportCollaboratorTests {
  @Test
  func `what the server sends goes to the writer it was given and not to the host's transport`()
    async throws
  {
    let inner = GatedTransport()
    let writer = SpyFrameWriting()
    let transport = ToolTransport(
      transport: inner,
      logger: inner.logger,
      writer: writer,
      reader: StubToolFrameReading(standIn: Data()),
    )
    await inner.release()
    await inner.release()

    try await transport.send(Data("A".utf8))
    try await transport.send(Data("B".utf8))

    #expect(await writer.frames == [Data("A".utf8), Data("B".utf8)])
    #expect(await inner.begun == 0)
  }

  @Test
  func `a frame its writer cannot write ends what comes in, and says why it failed`() async throws {
    let inner = GatedTransport()
    let transport = ToolTransport(
      transport: inner,
      logger: inner.logger,
      writer: SpyFrameWriting(failing: true),
      reader: StubToolFrameReading(standIn: Data()),
    )
    await inner.release()
    let reading = Task {
      for try await _ in await transport.receive() {}
    }

    await #expect(throws: SpyFrameWriting.Failure.self) {
      try await transport.send(Data("A".utf8))
    }
    // What comes in ends: the reading ends by itself, with nothing cancelling it.
    try await reading.value
  }

  @Test
  func `what the host sends comes in as the reader it was given reads it`() async throws {
    let (host, server) = await InMemoryTransport.createConnectedPair()
    let transport = ToolTransport(
      transport: server,
      logger: server.logger,
      writer: SpyFrameWriting(),
      reader: StubToolFrameReading(standIn: Data("read".utf8)),
    )

    try await transport.connect()
    try await host.connect()
    try await host.send(Data("sent".utf8))
    var received: Data?
    for try await frame in await transport.receive() {
      received = frame

      break
    }

    #expect(received == Data("read".utf8))
  }
}
