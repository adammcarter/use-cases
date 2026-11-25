import Foundation
import MCP
import Testing
import UseCasesCore

/// The built `use-cases mcp`, spoken to over real pipes as an agent's host speaks to it: the
/// only thing that proves standard output is protocol and nothing else, and that the framing is
/// right.
struct UseCasesMainWireTests {
  private func folder() throws -> URL {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "use-cases-wire-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: folder,
      withIntermediateDirectories: true,
    )

    return folder.resolvingSymlinksInPath()
  }

  /// Initialises the server as a host does, and answers what it says about itself.
  private func start(_ host: WireSession) async throws -> [String: Value] {
    let started = try await host.request(
      "initialize",
      [
        "protocolVersion": "2025-06-18",
        "capabilities": [:],
        "clientInfo": ["name": "wire", "version": "1"],
      ],
    )
    let result = try #require(started["result"]?.objectValue)
    #expect(result["capabilities"] == ["tools": [:]])
    #expect(result["instructions"] == nil)
    try await host.notify("notifications/initialized")

    return try #require(result["serverInfo"]?.objectValue)
  }

  @Test
  func `a host can start the server, list the tools, call them and end it by closing its input`(
  ) async throws {
    let program = try BuiltProgram.url()
    let workspace = try folder()
    defer {
      try? FileManager.default.removeItem(at: workspace)
    }
    let host = try WireSession(
      program: program,
      arguments: ["mcp"],
      folder: workspace,
    )

    let serverInfo = try await start(host)

    // the version over the wire is the one --version prints
    #expect(serverInfo["name"] == "use-cases")
    #expect(serverInfo["title"] == "Use Cases")
    #expect(serverInfo["version"] == .string(ProductVersion.current.release))

    // tools/list
    let listed = try await host.request("tools/list")
    let tools = try #require(listed["result"]?.objectValue?["tools"]?.arrayValue)
    #expect(tools.count == 13)

    // a call that needs no workspace
    let docs = try await host.request(
      "tools/call",
      ["name": "use_cases_docs", "arguments": [:]],
    )
    let answered = try #require(docs["result"]?.objectValue)
    #expect(answered["isError"] == false)
    #expect(answered["structuredContent"]?.objectValue?["command"] == "docs")

    // a call that is refused before it runs
    let refused = try await host.request(
      "tools/call",
      ["name": "use_cases_verify_tests", "arguments": [:]],
    )
    #expect(refused["result"]?.objectValue?["isError"] == true)

    // a tool that is no tool
    let unknown = try await host.request(
      "tools/call",
      ["name": "use_cases_init", "arguments": [:]],
    )
    #expect(unknown["error"]?.objectValue?["code"] == -32602)

    // closing the input ends the server, saying nothing more
    try await host.closeInput()
    #expect(await host.nextMessage() == nil)
    #expect(await host.exitCode() == 0)
    #expect(await host.standardError().isEmpty)
  }

  @Test
  func `the version the server says is the one the command prints`() async throws {
    let printed = try await AwaitedProgram.run(
      BuiltProgram.url(),
      arguments: ["--version"],
    )

    #expect(printed.output == "use-cases \(ProductVersion.current.release)\n")
  }

  @Test
  func `a tool runs its command in a workspace the call names`() async throws {
    let program = try BuiltProgram.url()
    let workspace = try folder()
    defer {
      try? FileManager.default.removeItem(at: workspace)
    }
    let setUp = try await AwaitedProgram.run(
      program,
      arguments: ["init", "--no-input"],
      folder: workspace,
    )
    #expect(setUp.termination == ProcessTermination(isExit: true, status: 0))

    let host = try WireSession(
      program: program,
      arguments: ["mcp"],
      folder: FileManager.default.temporaryDirectory,
    )
    _ = try await start(host)

    let validated = try await host.request(
      "tools/call",
      [
        "name": "use_cases_validate_files",
        "arguments": ["workspace": .string(workspace.path)],
      ],
    )
    let result = try #require(validated["result"]?.objectValue)
    #expect(result["isError"] == false)
    #expect(result["structuredContent"]?.objectValue?["valid"] == true)

    try await host.closeInput()
    #expect(await host.exitCode() == 0)
  }
}
