import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct McpCommandTests {
  private static let folder = URL(fileURLWithPath: "/work/shop")

  private func result(
    of arguments: [String],
    serving ending: ToolServingEnding,
  ) async -> (result: CommandResult, server: MockToolServing) {
    let server = MockToolServing(ending: ending)
    let result = await CommandLineRunner(
      loader: MockWorkspaceLoading.echoingStart,
      workingDirectory: Self.folder,
      toolServer: server,
    ).run(arguments: arguments)

    return (result, server)
  }

  @Test
  func `the host closing its input ends the server with exit 0 and says nothing`() async {
    let (result, _) = await result(of: ["mcp"], serving: .inputClosed)

    #expect(result.exitCode == 0)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.isEmpty)
  }

  @Test
  func `a process told to stop ends the server with exit 130, as a cancelled command does`() async {
    let (result, _) = await result(of: ["mcp"], serving: .stopped)

    #expect(result.exitCode == 130)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.isEmpty)
  }

  @Test
  func `a server that cannot run is a refusal on stderr, never a word on stdout`() async {
    let (result, _) = await result(of: ["mcp"], serving: .failed(reason: "no tools today"))

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError == "error: no tools today\n")
  }

  @Test
  func `the server starts in the folder the command runs from, finding the workspace itself`(
  ) async {
    let (_, server) = await result(of: ["mcp"], serving: .inputClosed)

    #expect(
      await server.requests == [
        MockToolServing.Request(workingDirectory: Self.folder, workspace: nil),
      ],
    )
  }

  @Test(arguments: [
    (["mcp", "--workspace", "/elsewhere"], "/elsewhere"),
    (["--workspace", "/elsewhere", "mcp"], "/elsewhere"),
    (["mcp", "--workspace", "sub"], "/work/shop/sub"),
  ])
  func `a workspace named is the one calls use when they name none`(
    arguments: [String],
    expected: String,
  ) async {
    let (_, server) = await result(of: arguments, serving: .inputClosed)

    #expect(await server.requests.map(\.workspace) == [expected])
  }

  @Test
  func `a build given no server says so and serves nothing`() async {
    let result = await CommandLineRunner(
      loader: MockWorkspaceLoading.echoingStart,
      workingDirectory: Self.folder,
    ).run(arguments: ["mcp"])

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError == "error: this build of use-cases has no MCP server\n")
  }

  @Test
  func `mcp is a command the help lists and the command line reads`() {
    #expect(UseCasesCommand.commandNames.contains(McpCommand.name))
    #expect(DesignedCommand.mcp.isBuilt)
  }
}
