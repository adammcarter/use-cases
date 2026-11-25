import Foundation
import MCP
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesMCP

struct ToolCallerRefusalTests {
  private func refusal(
    of arguments: [String: Value],
    tool: String,
    runner: MockCommandRunning,
  ) async throws -> (isError: Bool?, message: String) {
    let caller = try ToolCaller(
      catalogue: ToolCatalogue(schemas: MockOutputSchemaLoading()),
      program: URL(fileURLWithPath: "/opt/use-cases/use-cases"),
      workingDirectory: URL(fileURLWithPath: "/work/shop"),
      workspace: nil,
      runner: runner,
    )
    let result = try await caller.call(CallTool.Parameters(name: tool, arguments: arguments))

    guard case let .text(text, _, _)? = result.content.first else {
      return (result.isError, "")
    }

    let document = JSONValueReader().value(of: text)?.objectValue
    let error = document?["error"]?.objectValue

    #expect(error?["kind"] == "usage")

    return (result.isError, error?["message"]?.stringValue ?? "")
  }

  @Test
  func `a text holding NUL is a usage refusal naming the argument`() async throws {
    let runner = MockCommandRunning(printing: "{}")

    let answer = try await refusal(
      of: [
        "use_case": "a.b",
        "route": "r",
        "status": "pass",
        "message": "checked by hand\u{0} -- NOT really",
      ],
      tool: "use_cases_record_verdict",
      runner: runner,
    )

    #expect(answer.isError == true)
    #expect(answer.message.contains("message"))
    #expect(answer.message.contains("U+0000"))
    #expect(await runner.invocations.isEmpty)
  }

  @Test
  func `an item of a comma-joined list holding a comma is a usage refusal, and nothing runs`(
  ) async throws {
    let runner = MockCommandRunning(printing: "{}")

    let answer = try await refusal(
      of: ["query": "parse", "state": ["failed,verified"]],
      tool: "use_cases_search",
      runner: runner,
    )

    #expect(answer.isError == true)
    #expect(answer.message.contains("state"))
    #expect(await runner.invocations.isEmpty)
  }

  @Test
  func `an argument the SDK made into data is a usage refusal naming it, and nothing runs`(
  ) async throws {
    let runner = MockCommandRunning(printing: "{}")

    let answer = try await refusal(
      of: ["query": .data(mimeType: "text/plain", Data("hello".utf8))],
      tool: "use_cases_search",
      runner: runner,
    )

    #expect(answer.isError == true)
    #expect(answer.message.contains("query"))
    #expect(answer.message.contains("data URL"))
    #expect(await runner.invocations.isEmpty)
  }

  @Test
  func `data deep inside an argument is found too`() async throws {
    let runner = MockCommandRunning(printing: "{}")

    let answer = try await refusal(
      of: ["use_case": ["title": .data(Data("x".utf8))]],
      tool: "use_cases_save",
      runner: runner,
    )

    #expect(answer.isError == true)
    #expect(answer.message.contains("use_case"))
    #expect(await runner.invocations.isEmpty)
  }
}
