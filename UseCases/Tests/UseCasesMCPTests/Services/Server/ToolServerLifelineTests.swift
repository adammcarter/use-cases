import Foundation
import MCP
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesMCP

struct ToolServerLifelineTests {
  @Test
  func `the lifeline the server runs with is handed to every command a call starts`() async throws {
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    // Connected before the host speaks: a message to a transport that is not connected yet is lost.
    try await serverTransport.connect()
    let runner = MockCommandRunning(printing: #"{"command":"validate","output_version":1}"#)
    let server = ToolServer(
      program: URL(fileURLWithPath: "/opt/use-cases/use-cases"),
      workingDirectory: URL(fileURLWithPath: "/work/shop"),
      workspace: nil,
      runner: runner,
      schemas: MockOutputSchemaLoading(),
    )
    let serving = Task {
      try await server.run(
        transport: serverTransport,
        watcher: MockShutdownWatching(),
        lifeline: 42,
      )
    }
    let client = Client(name: "test", version: "1")
    _ = try await client.connect(transport: clientTransport)

    for _ in 0 ..< 2 {
      let context: RequestContext<CallTool.Result> = try await client.callTool(
        name: "use_cases_validate_files",
        arguments: [:],
      )
      _ = try await context.value
    }
    await client.disconnect()
    _ = try await serving.value

    #expect(await runner.invocations.map(\.lifeline) == [42, 42])
  }
}
