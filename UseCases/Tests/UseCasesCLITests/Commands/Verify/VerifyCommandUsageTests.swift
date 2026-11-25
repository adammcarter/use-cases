import Testing
@testable import UseCasesCLI

struct VerifyCommandUsageTests {
  private let workspace: VerifyWorkspace

  init() throws {
    workspace = try VerifyWorkspace()
  }

  @Test(arguments: [
    (["verify"], "say which step"),
    (["verify", "--finish", "--only", "x"], "--only belongs on"),
    (["verify", "--abort", "--only", "x"], "--only belongs on"),
    (["verify", "--start", "--run-id", "x"], "--run-id belongs on"),
    (["verify", "--run", "--run-id", "x"], "--run-id belongs on"),
    (["verify", "--start", "--finish"], "one step at a time"),
    (["verify", "--start", "--abort", "--finish"], "--start and --finish and --abort"),
    (["verify", "--bogus"], "--bogus"),
  ])
  func `a command line that is no request is a usage refusal with exit 2`(
    arguments: [String],
    message: String,
  ) async throws {
    let result = await workspace.run(["--json"] + arguments)
    let document = try result.document()

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains(message))
    #expect(document["command"] == .string("verify") || document["command"] == .null)
    #expect(document["error"]?["kind"] == .string("usage"))
    #expect(workspace.runs().isEmpty)
  }

  @Test
  func `a plain verify names every step`() async {
    let result = await workspace.run(["verify"])

    #expect(result.exitCode == 2)
    #expect(result.standardError.contains("--start"))
    #expect(result.standardError.contains("--finish"))
    #expect(result.standardError.contains("--run"))
    #expect(result.standardOutput.isEmpty)
  }

  @Test
  func `an unknown validation in --only is a usage refusal`() async throws {
    let result = await workspace.run(["--json", "verify", "--start", "--only", "unit-tests,nope"])
    let document = try result.document()

    #expect(result.exitCode == 2)
    #expect(document["error"]?["kind"] == .string("usage"))
    #expect(result.standardError.contains("nope"))
    #expect(workspace.runs().isEmpty)
  }

  @Test
  func `an empty name in --only names no validation`() async {
    let result = await workspace.run(["verify", "--start", "--only", "unit-tests,"])

    #expect(result.exitCode == 2)
    #expect(workspace.runs().isEmpty)
  }
}
