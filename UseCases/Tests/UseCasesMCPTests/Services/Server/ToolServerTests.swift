import Foundation
import Logging
import MCP
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesMCP

struct ToolServerTests {
  private static let program = URL(fileURLWithPath: "/opt/use-cases/use-cases")
  private static let folder = URL(fileURLWithPath: "/work/shop")

  /// A server on an in-memory transport, over the runner, and a client connected to it.
  private struct Session {
    let client: Client
    let serving: Task<ToolServerEnding, any Error>
    let initialization: Initialize.Result
    let server: RecordingTransport
  }

  /// The server's end of the in-memory pair, which remembers every frame the server sends.
  private actor RecordingTransport: Transport {
    nonisolated let logger: Logger

    /// The frames the server has sent, in the order it sent them.
    private(set) var sent: [Data] = []

    private let transport: InMemoryTransport
    private let incoming: AsyncThrowingStream<Data, any Error>

    /// - Parameter transport: The server's end, already connected.
    init(_ transport: InMemoryTransport) async {
      logger = transport.logger
      self.transport = transport
      incoming = await transport.receive()
    }

    func connect() async throws {
      try await transport.connect()
    }

    func disconnect() async {
      await transport.disconnect()
    }

    func send(_ data: Data) async throws {
      sent.append(data)
      try await transport.send(data)
    }

    func receive() -> AsyncThrowingStream<Data, any Error> {
      incoming
    }

    /// The identifiers of the requests the server has answered, with a result or an error.
    func answered() -> [Value] {
      var identifiers: [Value] = []

      for frame in sent {
        guard
          let message = try? JSONDecoder().decode([String: Value].self, from: frame),
          message["result"] != nil || message["error"] != nil,
          let identifier = message["id"]
        else {
          continue
        }

        identifiers.append(identifier)
      }

      return identifiers
    }
  }

  private func session(
    running runner: MockCommandRunning,
    watcher: any ShutdownWatching = MockShutdownWatching(),
  ) async throws -> Session {
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    // Connected before the host speaks: a message to a transport that is not connected yet is lost.
    try await serverTransport.connect()
    let recording = await RecordingTransport(serverTransport)
    let server = ToolServer(
      program: Self.program,
      workingDirectory: Self.folder,
      workspace: nil,
      runner: runner,
      schemas: MockOutputSchemaLoading(),
    )
    let serving = Task {
      try await server.run(
        transport: recording,
        watcher: watcher,
      )
    }
    let client = Client(name: "test", version: "1")
    let initialization = try await client.connect(transport: clientTransport)

    return Session(
      client: client,
      serving: serving,
      initialization: initialization,
      server: recording,
    )
  }

  private func identifier(of request: ID) throws -> Value {
    try JSONDecoder().decode(Value.self, from: JSONEncoder().encode(request))
  }

  @Test
  func `the server says it serves tools and nothing else, and says nothing the host did not ask`(
  ) async throws {
    let session = try await session(running: MockCommandRunning(printing: "{}"))

    #expect(session.initialization.capabilities == Server.Capabilities(tools: .init()))
    #expect(session.initialization.instructions == nil)
    #expect(session.initialization.protocolVersion == Version.latest)

    await session.client.disconnect()
    _ = try await session.serving.value
  }

  @Test
  func `the server is called Use Cases and says the version use-cases --version prints`(
  ) async throws {
    let session = try await session(running: MockCommandRunning(printing: "{}"))

    #expect(session.initialization.serverInfo.name == "use-cases")
    #expect(session.initialization.serverInfo.title == "Use Cases")
    #expect(session.initialization.serverInfo.version == ProductVersion.current.release)

    await session.client.disconnect()
    _ = try await session.serving.value
  }

  @Test
  func `the thirteen tools are listed with what the catalogue shows`() async throws {
    let session = try await session(running: MockCommandRunning(printing: "{}"))

    let (tools, nextCursor) = try await session.client.listTools()

    #expect(tools.map(\.name) == ToolDefinition.all.map(\.name))
    #expect(nextCursor == nil)

    await session.client.disconnect()
    _ = try await session.serving.value
  }

  @Test
  func `a call is answered with the command's document, as text and as structured content`(
  ) async throws {
    let runner =
      MockCommandRunning(printing: #"{"command":"validate","output_version":1,"valid":true}"#)
    let session = try await session(running: runner)

    let context: RequestContext<CallTool.Result> = try await session.client.callTool(
      name: "use_cases_validate_files",
      arguments: ["workspace": "/w"],
    )
    let result = try await context.value

    #expect(result.isError == false)
    #expect(result.structuredContent?.objectValue?["valid"] == true)
    #expect(
      await runner.invocations.first?.arguments
        == ["/opt/use-cases/use-cases", "validate", "--json", "--workspace", "/w"],
    )

    await session.client.disconnect()
    _ = try await session.serving.value
  }

  @Test
  func `a call to a tool that does not exist is a protocol error, invalid params`() async throws {
    let runner = MockCommandRunning(printing: "{}")
    let session = try await session(running: runner)

    do {
      _ = try await session.client.callTool(name: "use_cases_init", arguments: [:]) as (
        content: [Tool.Content],
        isError: Bool?,
      )
      Issue.record("an unknown tool was answered")
    } catch let error as MCPError {
      #expect(error.code == -32602)
    }
    #expect(await runner.invocations.isEmpty)

    await session.client.disconnect()
    _ = try await session.serving.value
  }

  @Test
  func `bad arguments are a result marked as an error, not a protocol error, and run nothing`(
  ) async throws {
    let runner = MockCommandRunning(printing: "{}")
    let session = try await session(running: runner)

    let context: RequestContext<CallTool.Result> = try await session.client.callTool(
      name: "use_cases_verify_tests",
      arguments: [:],
    )
    let result = try await context.value

    #expect(result.isError == true)
    #expect(await runner.invocations.isEmpty)

    await session.client.disconnect()
    _ = try await session.serving.value
  }

  @Test
  func `calls do not wait for one another`() async throws {
    let runner = MockCommandRunning(.runningUntilCancelled)
    let session = try await session(running: runner)

    for _ in 0 ..< 2 {
      let _: RequestContext<CallTool.Result> = try await session.client.callTool(
        name: "use_cases_validate_files",
        arguments: [:],
      )
    }
    var started = 0
    for await _ in runner.starts {
      started += 1

      if started == 2 {
        break
      }
    }

    #expect(await runner.invocations.count == 2)

    await session.client.disconnect()
    _ = try await session.serving.value
  }

  @Test
  func `a cancelled request stops its command and is not answered`() async throws {
    let runner = MockCommandRunning(.runningUntilCancelled)
    let session = try await session(running: runner)

    let context: RequestContext<CallTool.Result> = try await session.client.callTool(
      name: "use_cases_verify_tests",
      arguments: ["step": "run"],
    )
    for await _ in runner.starts {
      break
    }

    try await session.client.cancelRequest(context.requestID)
    var endings: [CommandEnding] = []
    for await ending in runner.endings {
      endings.append(ending)
      break
    }

    #expect(endings == [.cancelled])

    // A request made once the command has ended is answered; then the server is ended, so every
    // frame it sent is in. None answers the cancelled call.
    let ping = try await session.client.send(Ping.request())
    _ = try await ping.value
    await session.client.disconnect()
    _ = try await session.serving.value

    let answered = await session.server.answered()
    #expect(try answered.contains(identifier(of: ping.requestID)))
    #expect(
      try !answered.contains(identifier(of: context.requestID)),
      "the cancelled call was answered",
    )
  }

  @Test
  func `the host closing its input cancels the calls running, waits for them, and ends the server`(
  ) async throws {
    let runner = MockCommandRunning(.runningUntilCancelled)
    let session = try await session(running: runner)

    let _: RequestContext<CallTool.Result> = try await session.client.callTool(
      name: "use_cases_verify_tests",
      arguments: ["step": "run"],
    )
    for await _ in runner.starts {
      break
    }

    await session.client.disconnect()
    let ending = try await session.serving.value

    #expect(ending == .inputClosed)
    var endings: [CommandEnding] = []
    for await ending in runner.endings {
      endings.append(ending)
      break
    }
    #expect(endings == [.cancelled])
  }

  @Test
  func `a process told to stop ends the server, with the calls running cancelled`() async throws {
    let runner = MockCommandRunning(.runningUntilCancelled)
    let watcher = MockShutdownWatching()
    let session = try await session(
      running: runner,
      watcher: watcher,
    )

    let _: RequestContext<CallTool.Result> = try await session.client.callTool(
      name: "use_cases_verify_tests",
      arguments: ["step": "run"],
    )
    for await _ in runner.starts {
      break
    }

    watcher.stop()
    let ending = try await session.serving.value

    #expect(ending == .stopped)
    var endings: [CommandEnding] = []
    for await ending in runner.endings {
      endings.append(ending)
      break
    }
    #expect(endings == [.cancelled])
    await session.client.disconnect()
  }

  @Test
  func `tools that cannot be made stop the server before it serves`() async {
    let (_, serverTransport) = await InMemoryTransport.createConnectedPair()
    let server = ToolServer(
      program: Self.program,
      workingDirectory: Self.folder,
      workspace: nil,
      runner: MockCommandRunning(printing: "{}"),
      schemas: MockOutputSchemaLoading(refusing: .missing(file: "cli-validate.schema.json")),
    )

    await #expect(throws: ToolServerError.self) {
      try await server.run(
        transport: serverTransport,
        watcher: MockShutdownWatching(),
      )
    }
  }
}
