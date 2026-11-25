import Foundation
import MCP
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesMCP

struct ToolCallerTests {
  private static let program = URL(fileURLWithPath: "/opt/use-cases/use-cases")
  private static let folder = URL(fileURLWithPath: "/work/shop")

  private func caller(
    running runner: MockCommandRunning,
    workspace: String? = nil,
  ) throws -> ToolCaller {
    try ToolCaller(
      catalogue: ToolCatalogue(schemas: MockOutputSchemaLoading()),
      program: Self.program,
      workingDirectory: Self.folder,
      workspace: workspace,
      runner: runner,
    )
  }

  private func text(of result: CallTool.Result) -> String {
    guard case let .text(text, _, _)? = result.content.first else {
      return ""
    }

    return text
  }

  @Test
  func `a call runs its command by the program's real path, from the folder the server started in`(
  ) async throws {
    let runner = MockCommandRunning(printing: #"{"command":"validate","output_version":1}"#)

    let result = try await caller(running: runner).call(
      CallTool.Parameters(name: "use_cases_validate_files", arguments: ["workspace": "/w"]),
    )

    #expect(result.isError == false)
    #expect(
      await runner.invocations == [
        CommandInvocation(
          arguments: ["/opt/use-cases/use-cases", "validate", "--json", "--workspace", "/w"],
          workingDirectory: Self.folder,
        ),
      ],
    )
  }

  @Test
  func `a call with no arguments at all runs its command`() async throws {
    let runner = MockCommandRunning(printing: #"{"command":"validate"}"#)

    let result = try await caller(running: runner).call(
      CallTool.Parameters(name: "use_cases_validate_files"),
    )

    #expect(result.isError == false)
    #expect(await runner.invocations.count == 1)
  }

  @Test
  func `what a tool puts on standard input reaches the command`() async throws {
    let runner = MockCommandRunning(printing: #"{"command":"search"}"#)

    _ = try await caller(running: runner).call(
      CallTool.Parameters(name: "use_cases_search", arguments: ["like": ["title": "T"]]),
    )

    #expect(await runner.invocations.first?.standardInput == #"{"title":"T"}"#)
  }

  @Test
  func `the workspace the server was given is used when the call names none`() async throws {
    let runner = MockCommandRunning(printing: #"{"command":"links"}"#)

    _ = try await caller(running: runner, workspace: "/given").call(
      CallTool.Parameters(name: "use_cases_links"),
    )

    #expect(
      await runner.invocations.first?.arguments.suffix(2) == ["--workspace", "/given"],
    )
  }

  @Test
  func `an unknown tool is the one call that has no result`() async throws {
    let runner = MockCommandRunning(printing: "{}")

    await #expect(throws: ToolCallError.unknownTool("use_cases_init")) {
      try await caller(running: runner).call(CallTool.Parameters(name: "use_cases_init"))
    }
    #expect(await runner.invocations.isEmpty)
  }

  @Test(arguments: [
    ([:] as [String: Value], "needs step"),
    (["step": "run", "shell": "rm -rf /"], "takes no shell"),
    (["step": 3], "step"),
  ])
  func `a call with bad arguments is refused before anything runs`(
    arguments: [String: Value],
    expected: String,
  ) async throws {
    let runner = MockCommandRunning(printing: "{}")

    let result = try await caller(running: runner).call(
      CallTool.Parameters(name: "use_cases_verify_tests", arguments: arguments),
    )

    let document = try #require(JSONValueReader().value(of: text(of: result))?.objectValue)
    #expect(result.isError == true)
    #expect(result.structuredContent == nil)
    #expect(document["command"] == "verify")
    #expect(document["error"]?.objectValue?["kind"] == "usage")
    #expect(document["error"]?.objectValue?["message"]?.stringValue?.contains(expected) == true)
    #expect(await runner.invocations.isEmpty)
  }

  @Test
  func `a command that cannot be started is a tool error saying why`() async throws {
    let runner = MockCommandRunning(.failing(.couldNotRun(reason: "no such file")))

    let result = try await caller(running: runner).call(
      CallTool.Parameters(name: "use_cases_validate_files"),
    )

    let document = try #require(JSONValueReader().value(of: text(of: result))?.objectValue)
    #expect(result.isError == true)
    #expect(document["error"]?.objectValue?["kind"] == "refused")
    #expect(
      document["error"]?.objectValue?["message"]?.stringValue
        == "use-cases could not be run: no such file",
    )
  }

  @Test
  func `a command that was cancelled has no result to give`() async throws {
    let runner = MockCommandRunning(.runningUntilCancelled)
    let caller = try caller(running: runner)

    let call = Task {
      try await caller.call(CallTool.Parameters(name: "use_cases_validate_files"))
    }
    for await _ in runner.starts {
      break
    }
    call.cancel()

    await #expect(throws: ToolCallError.cancelled) {
      try await call.value
    }
  }
}
