import Foundation
import Testing
import UseCasesCore
@testable import UseCasesCLI

struct CommandLineRunnerTests {
  private static let nowhere = URL(fileURLWithPath: "/nowhere")

  private func runner(
    _ loader: MockWorkspaceLoading = .echoingStart,
  ) -> CommandLineRunner {
    CommandLineRunner(
      loader: loader,
      workingDirectory: Self.nowhere,
    )
  }

  private func document(_ result: CommandResult) throws -> [String: Any] {
    let value = try JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8))

    return try #require(value as? [String: Any])
  }

  @Test
  func `the version is printed for a person`() async {
    let result = await runner().run(arguments: ["--version"])

    #expect(result.exitCode == 0)
    #expect(result.standardOutput.hasPrefix("use-cases "))
    #expect(result.standardError.isEmpty)
  }

  @Test
  func `the version with json is one document with the contract and the store`() async throws {
    let result = await runner().run(arguments: ["--json", "--version"])
    let found = try document(result)

    #expect(result.exitCode == 0)
    #expect(found["command"] as? String == "version")
    #expect(found["contract"] as? Int == 1)
    #expect(found["store"] as? Int == 1)
  }

  @Test(arguments: [[], ["--help"]])
  func `the bare command and help print the help and exit 0`(arguments: [String]) async {
    let result = await runner().run(arguments: arguments)

    #expect(result.exitCode == 0)
    #expect(result.standardOutput.contains("validate"))
  }

  @Test
  func `a flag that does not exist is a usage error with exit 2, not ArgumentParser's own code`(
  ) async {
    let result = await runner().run(arguments: ["--nope"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.hasPrefix("error: "))
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func `with json a usage error is also a document of kind usage, with the message in stderr`(
  ) async
    throws
  {
    let result = await runner().run(arguments: [
      "--workspace",
      "/w",
      "--json",
      "validate",
      "--bogus",
    ])
    let found = try document(result)
    let error = try #require(found["error"] as? [String: String])
    let message = try #require(error["message"])

    #expect(result.exitCode == 2)
    #expect(found["command"] as? String == "validate")
    #expect(error["kind"] == "usage")
    #expect(result.standardError.contains(message))
  }

  @Test
  func `a command it does not know is a usage error whose command is null`() async throws {
    let result = await runner().run(arguments: ["--json", "nosuch"])
    let found = try document(result)

    #expect(result.exitCode == 2)
    #expect(found["command"] is NSNull)
    #expect((found["error"] as? [String: String])?["kind"] == "usage")
  }

  @Test
  func `a command it does not know says invalid choice, naming it`() async {
    let result = await runner().run(arguments: ["--workspace", "/w", "nosuch"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("invalid choice: 'nosuch'"))
    #expect(result.standardOutput.isEmpty)
  }

  @Test(arguments: [
    ["render", "proposal", "--file", "p.yml"],
    ["--json", "render", "results", "--file", "-"],
  ])
  func `a designed command the surface says is not built yet is exit 3, never invalid choice`(
    arguments: [String],
  ) async {
    let result = await CommandLineRunner(
      loader: MockWorkspaceLoading.echoingStart,
      surface: MockCommandSurface(reply: .notBuiltYet(command: "render")),
      workingDirectory: Self.nowhere,
    ).run(arguments: arguments)

    #expect(result.exitCode == 3)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.hasSuffix(" is not built yet\n"))
    #expect(!result.standardError.contains("invalid choice"))
  }

  @Test(arguments: [[], ["--help"], ["--workspace", "/w"]])
  func `the help is the command list of chapter 16, every command in it`(
    arguments: [String],
  ) async {
    let result = await runner().run(arguments: arguments)

    #expect(result.exitCode == 0)
    #expect(result.standardOutput.contains("use-cases verify --start | --finish | --run | --abort"))
    #expect(result.standardOutput.contains("use-cases record --interactive"))
    #expect(result.standardOutput.contains("use-cases mcp"))
  }

  @Test(arguments: [["help"], ["help", "validate"], ["--json", "help", "links"]])
  func `help is no command of chapter 16, so it is an invalid choice like any other word`(
    arguments: [String],
  ) async {
    let result = await runner().run(arguments: arguments)

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("invalid choice: 'help'"))
    #expect(result.standardOutput.isEmpty || result.standardOutput.hasPrefix("{"))
  }

  @Test
  func `the command surface is taken through init: what it answers is the answer`() async {
    let answer = CommandResult.done("from the surface")
    let result = await CommandLineRunner(
      loader: MockWorkspaceLoading.echoingStart,
      surface: MockCommandSurface(reply: answer),
      workingDirectory: Self.nowhere,
    ).run(arguments: ["validate"])

    #expect(result == answer)
  }

  @Test
  func `a surface with no answer leaves the command line to the commands`() async {
    let result = await CommandLineRunner(
      loader: MockWorkspaceLoading.echoingStart,
      surface: MockCommandSurface(reply: nil),
      workingDirectory: Self.nowhere,
    ).run(arguments: ["validate"])

    #expect(result.standardError.contains("searchingUpward"))
  }

  @Test
  func `validate asks the loader to search upward from the current folder`() async {
    let result = await runner().run(arguments: ["validate"])

    #expect(result.standardError.contains("searchingUpward"))
    #expect(result.standardError.contains("/nowhere"))
  }

  @Test
  func `validate with a workspace asks the loader for exactly that folder`() async {
    let result = await runner().run(arguments: ["--workspace", "/w/shop", "validate"])

    #expect(result.standardError.contains("workspace"))
    #expect(result.standardError.contains("/w/shop"))
  }

  // @use-case:cli.version-and-help#swift-tests.command-help
  @Test(arguments: [
    ["validate", "--help"],
    ["validate", "-h"],
    ["--json", "validate", "--help"],
  ])
  func `help for validate is validate's own help and exits 0`(arguments: [String]) async {
    let result = await runner().run(arguments: arguments)

    #expect(result.exitCode == 0)
    #expect(result.standardOutput.contains("use-cases validate"))
    #expect(result.standardOutput.contains("Runs no test"))
    #expect(result.standardError.isEmpty)
  }

  // @use-case:end cli.version-and-help#swift-tests.command-help

  @Test(arguments: [["--help"], ["-h"], ["--json", "--help"], ["-h", "--json"]])
  func `an explicit request for help prints plain help, with json or without`(
    arguments: [String],
  ) async {
    let result = await runner().run(arguments: arguments)

    #expect(result.exitCode == 0)
    #expect(result.standardOutput.contains("validate"))
    #expect(!result.standardOutput.hasPrefix("{"))
    #expect(result.standardError.isEmpty)
  }

  @Test
  func `json with no command is a usage refusal as a script expects it`() async throws {
    let result = await runner().run(arguments: ["--json"])
    let found = try document(result)
    let error = try #require(found["error"] as? [String: String])

    #expect(result.exitCode == 2)
    #expect(found["command"] is NSNull)
    #expect(error["kind"] == "usage")
    #expect(try result.standardError.contains(#require(error["message"])))
  }

  @Test
  func `the bare command, with no json, prints the help`() async {
    let result = await runner().run(arguments: [])

    #expect(result.exitCode == 0)
    #expect(result.standardOutput.contains("validate"))
  }

  // @use-case:cli.version-and-help#swift-tests.command-help
  @Test(arguments: [
    ["links", "--help"],
    ["links", "-h"],
    ["--json", "links", "--help"],
  ])
  func `help for links is links' own help and exits 0`(arguments: [String]) async {
    let result = await runner().run(arguments: arguments)

    #expect(result.exitCode == 0)
    #expect(result.standardOutput.contains("use-cases links"))
    #expect(result.standardOutput.contains("Which code each use case is tied to"))
    #expect(result.standardError.isEmpty)
  }

  // @use-case:end cli.version-and-help#swift-tests.command-help

  @Test
  func `the command list names links`() async {
    let result = await runner().run(arguments: ["--help"])

    #expect(result.standardOutput.contains("links"))
  }

  @Test
  func `a links command line that cannot be read is a usage refusal of links`() async throws {
    let result = await runner().run(arguments: ["--json", "links", "--bogus"])
    let found = try document(result)

    #expect(result.exitCode == 2)
    #expect(found["command"] as? String == "links")
  }
}
