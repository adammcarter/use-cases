import Foundation
import MCP
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesMCP

/// What the host writes in a tool's arguments reaches the command exactly, whatever it looks like.
struct ToolServerArgumentsTests {
  private func serve(
    running runner: MockCommandRunning,
    calling tool: String,
    with arguments: [String: Value],
  ) async throws -> CallTool.Result {
    let (clientTransport, serverTransport) = await InMemoryTransport.createConnectedPair()
    // Connected before the host speaks: a message to a transport that is not connected yet is lost.
    try await serverTransport.connect()
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
      )
    }
    let client = Client(name: "test", version: "1")
    _ = try await client.connect(transport: clientTransport)
    let context: RequestContext<CallTool.Result> = try await client.callTool(
      name: tool,
      arguments: arguments,
    )
    let result = try await context.value
    await client.disconnect()
    _ = try await serving.value

    return result
  }

  private static let looksLikeData = [
    "data: retention, deletion and export",
    "data:,hello",
    "data: rows, all",
    "data:text/plain;base64,aGVsbG8=",
  ]

  @Test(arguments: looksLikeData)
  func `a use case whose text looks like a data URL is saved as written`(
    text: String,
  ) async throws {
    let runner = MockCommandRunning(printing: #"{"command":"save","output_version":1}"#)
    let useCase: Value = ["id": "x", "title": .string(text), "description": .string(text)]

    let result = try await serve(
      running: runner,
      calling: "use_cases_save",
      with: ["use_case": useCase],
    )

    let input = try #require(await runner.invocations.first?.standardInput)
    #expect(result.isError == false)
    #expect(try JSONDecoder().decode(PlainJSON.self, from: Data(input.utf8)).value == useCase)
  }

  @Test(arguments: looksLikeData)
  func `a query or a group that looks like a data URL is passed as written`(
    text: String,
  ) async throws {
    let runner = MockCommandRunning(printing: #"{"command":"search","output_version":1}"#)

    let result = try await serve(
      running: runner,
      calling: "use_cases_search",
      with: ["query": .string(text), "group": .string(text)],
    )

    #expect(result.isError == false)
    #expect(
      await runner.invocations.first?.arguments
        == ["/opt/use-cases/use-cases", "search", "--json", "--group", text, "--", text],
    )
  }

  @Test
  func `a use case to look for that looks like a data URL is passed as written`() async throws {
    let runner = MockCommandRunning(printing: #"{"command":"search","output_version":1}"#)
    let like: Value = ["title": "data:,hello", "intent": "data: rows, all"]

    _ = try await serve(
      running: runner,
      calling: "use_cases_search",
      with: ["like": like],
    )

    let input = try #require(await runner.invocations.first?.standardInput)
    #expect(try JSONDecoder().decode(PlainJSON.self, from: Data(input.utf8)).value == like)
  }

  @Test
  func `a batch to apply and an input to render that look like data URLs are passed as written`(
  ) async throws {
    let runner = MockCommandRunning(printing: #"{"command":"apply","output_version":1}"#)
    let save: Value = [["id": "x", "title": "data:,hello"]]

    _ = try await serve(
      running: runner,
      calling: "use_cases_apply",
      with: ["save": save, "approved_by": "data:,Sam"],
    )

    let input = try #require(await runner.invocations.first?.standardInput)
    let document = try JSONDecoder().decode(PlainJSON.self, from: Data(input.utf8)).value
    #expect(document.objectValue?["save"] == save)
    #expect(
      await runner.invocations.first?.arguments.contains("--approved-by")
        == true,
    )
    #expect(await runner.invocations.first?.arguments.contains("data:,Sam") == true)
  }

  @Test
  func `an argument that is a number or a flag reaches the command as it was sent`() async throws {
    let runner = MockCommandRunning(printing: #"{"command":"search","output_version":1}"#)

    _ = try await serve(
      running: runner,
      calling: "use_cases_search",
      with: ["query": "x", "page_size": 5, "full": true],
    )

    #expect(
      await runner.invocations.first?.arguments
        == [
          "/opt/use-cases/use-cases",
          "search",
          "--json",
          "--full",
          "--page-size",
          "5",
          "--",
          "x",
        ],
    )
  }
}
