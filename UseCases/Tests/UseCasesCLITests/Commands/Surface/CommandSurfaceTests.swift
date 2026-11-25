import Foundation
import Testing
@testable import UseCasesCLI

struct CommandSurfaceTests {
  private func answer(_ arguments: [String]) -> CommandResult? {
    CommandSurface().answer(to: arguments)
  }

  @Test(arguments: [
    [],
    ["--help"],
    ["-h"],
    ["--json", "--help"],
    ["--workspace", "/w", "-h"],
  ])
  func `the bare command and a request for help print the command list and exit 0`(
    arguments: [String],
  ) {
    let result = answer(arguments)

    #expect(result?.exitCode == 0)
    #expect(result?.standardOutput == CommandList.text + "\n")
    #expect(result?.standardError.isEmpty == true)
  }

  @Test(arguments: [
    ["--json"],
    ["--version"],
    ["--workspace", "/w"],
    ["validate", "--help"],
    ["status", "shop.pay", "--group", "release"],
    ["--workspace", "/w", "--json", "links"],
    ["verify", "--start"],
    ["record", "shop.pay.card", "unit-tests", "pass"],
  ])
  func `a command that is built is left to be read`(arguments: [String]) {
    #expect(answer(arguments) == nil)
  }

  @Test(arguments: ["nosuch", "Validate", "statu", "validate2"])
  func `a word that is no command is a usage error naming the word and the choices`(
    word: String,
  ) throws {
    let result = try #require(answer(["--workspace", "/w", word]))

    #expect(result.exitCode == 2)
    #expect(result.standardOutput.isEmpty)
    #expect(result.standardError.contains("invalid choice: '\(word)'"))
    #expect(result.standardError.contains("validate, status, verify, record, links"))
  }

  @Test(arguments: [["help"], ["help", "validate"], ["help", "show"], ["--json", "help"]])
  func `help is no command, so it is an invalid choice like any word that is none`(
    arguments: [String],
  ) throws {
    let result = try #require(answer(arguments))

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("invalid choice: 'help'"))
  }

  @Test
  func `the usage error of a command line asking for json is a document with no command`(
  ) throws {
    let result = try #require(answer(["--json", "nosuch"]))
    let found = try #require(
      JSONSerialization.jsonObject(with: Data(result.standardOutput.utf8)) as? [String: Any],
    )
    let error = try #require(found["error"] as? [String: String])

    #expect(result.exitCode == 2)
    #expect(found["command"] is NSNull)
    #expect(error["kind"] == "usage")
    #expect(error["message"]?.contains("invalid choice: 'nosuch'") == true)
    #expect(result.standardError.contains("invalid choice: 'nosuch'"))
  }

  @Test(arguments: DesignedCommand.allCases.filter { !$0.isBuilt })
  func `a designed command not built yet is exit 3 whatever it is given, never invalid choice`(
    command: DesignedCommand,
  ) throws {
    for arguments in [[command.rawValue], [
      "--json",
      command.rawValue,
      "--file",
      "-",
      "--dry-run",
    ]] {
      let result = try #require(answer(arguments))

      #expect(result.exitCode == 3)
      #expect(result.standardOutput.isEmpty)
      #expect(result.standardError == "use-cases \(command.rawValue) is not built yet\n")
    }
  }
}
