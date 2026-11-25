import Foundation
import MCP
import Testing
@testable import UseCasesMCP

struct ToolTransportTests {
  @Test
  func `what the host sends comes in with the arguments of its calls set aside`() async throws {
    let (host, server) = await InMemoryTransport.createConnectedPair()
    let arguments = ToolCallArguments()
    let transport = ToolTransport(
      transport: server,
      logger: server.logger,
      arguments: arguments,
    )

    try await transport.connect()
    try await host.connect()
    try await host.send(
      Data(
        #"""
        {"jsonrpc":"2.0","id":1,"method":"tools/call",\#
        "params":{"name":"n","arguments":{"q":"data:,x"}}}
        """#.utf8,
      ),
    )
    var received: Data?
    for try await frame in await transport.receive() {
      received = frame

      break
    }

    let frame = try #require(received)
    let standIn = try #require(
      JSONDecoder().decode(PlainJSON.self, from: frame).value
        .objectValue?["params"]?.objectValue?["arguments"]?.objectValue,
    )
    #expect(Array(standIn.keys) == [ToolCallArguments.keyMember])
    #expect(await arguments.arguments(read: standIn) == ["q": "data:,x"])
  }

  @Test
  func `frames the host sends come in in the order it sent them`() async throws {
    let (host, server) = await InMemoryTransport.createConnectedPair()
    let transport = ToolTransport(
      transport: server,
      logger: server.logger,
      arguments: ToolCallArguments(),
    )

    try await transport.connect()
    try await host.connect()

    var sent: [String] = []

    for number in 0 ..< 50 {
      sent.append("n\(number)")
      try await host.send(
        JSONEncoder().encode(["jsonrpc": "2.0", "method": "n\(number)"]),
      )
    }
    var methods: [String] = []
    for try await frame in await transport.receive() {
      try methods.append(
        JSONDecoder().decode(PlainJSON.self, from: frame).value.objectValue?["method"]?.stringValue
          ?? "",
      )

      if methods.count == 50 {
        break
      }
    }

    #expect(methods == sent)
  }

  @Test
  func `what the server sends goes out whole, one frame after another`() async throws {
    let inner = GatedTransport()
    let transport = ToolTransport(
      transport: inner,
      logger: inner.logger,
      arguments: ToolCallArguments(),
    )
    await inner.release()
    await inner.release()

    try await transport.send(Data("A".utf8))
    try await transport.send(Data("B".utf8))

    #expect(
      await inner.events == [.began("A"), .ended("A"), .began("B"), .ended("B")],
    )
  }

  @Test
  func `a frame that cannot be written ends what comes in, and says why it failed`() async throws {
    let inner = GatedTransport(failing: ["A"])
    let transport = ToolTransport(
      transport: inner,
      logger: inner.logger,
      arguments: ToolCallArguments(),
    )
    await inner.release()
    let reading = Task {
      for try await _ in await transport.receive() {}
    }

    await #expect(throws: GatedTransport.Failure.self) {
      try await transport.send(Data("A".utf8))
    }
    // What comes in ends: the reading ends by itself, with nothing cancelling it.
    try await reading.value
  }
}
