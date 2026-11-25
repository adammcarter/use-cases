import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct McpCommandWorkspaceTests {
  private static let folder = URL(fileURLWithPath: "/work/shop")

  private func result(
    of arguments: [String],
    existing: Set<String>,
  ) async -> (result: CommandResult, server: MockToolServing) {
    let server = MockToolServing(ending: .inputClosed)
    let result = await CommandLineRunner(
      loader: MockWorkspaceLoading.echoingStart,
      workingDirectory: Self.folder,
      toolServer: server,
      folders: MockFolderChecking(existing: existing),
    ).run(arguments: arguments)

    return (result, server)
  }

  @Test(arguments: [
    (["mcp", "--workspace", "/missing"], "/missing"),
    (["--workspace", "/missing", "mcp"], "/missing"),
    (["mcp", "--workspace", "sub"], "/work/shop/sub"),
  ])
  func `a workspace that is no folder is refused at the start, on standard error, with exit 2`(
    arguments: [String],
    path: String,
  ) async {
    let (result, server) = await result(of: arguments, existing: ["/work/shop"])

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(
      result.standardError == "error: '\(path)' has no use-cases.yml; the workspace root is the "
        + "folder whose use-cases.yml says root: true\n",
    )
    #expect(await server.requests.isEmpty)
  }

  @Test
  func `a workspace that is a folder is served`() async {
    let (result, server) = await result(
      of: ["mcp", "--workspace", "/elsewhere"],
      existing: ["/elsewhere"],
    )

    #expect(result.exitCode == 0)
    #expect(await server.requests.map(\.workspace) == ["/elsewhere"])
  }

  @Test
  func `no workspace named, no folder is asked about`() async {
    let (result, server) = await result(of: ["mcp"], existing: [])

    #expect(result.exitCode == 0)
    #expect(await server.requests.count == 1)
  }

  @Test
  func `the real check says a folder is one, and a file or a missing name is not`() throws {
    let folder = FileManager.default.temporaryDirectory
      .appending(path: "use-cases-folders-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: folder)
    }
    let file = folder.appending(path: "file")
    try Data().write(to: file)

    #expect(ExistingFolders().isFolder(folder))
    #expect(!ExistingFolders().isFolder(file))
    #expect(!ExistingFolders().isFolder(folder.appending(path: "missing")))
  }
}
