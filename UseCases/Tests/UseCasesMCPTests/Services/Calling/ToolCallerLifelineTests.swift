import Foundation
import MCP
import Testing
import UseCasesCore
import UseCasesTestSupport
@testable import UseCasesMCP

struct ToolCallerLifelineTests {
  private func invocations(lifeline: Int32?) async throws -> [CommandInvocation] {
    let runner = MockCommandRunning(printing: #"{"command":"validate"}"#)
    let caller = try ToolCaller(
      catalogue: ToolCatalogue(schemas: MockOutputSchemaLoading()),
      program: URL(fileURLWithPath: "/opt/use-cases/use-cases"),
      workingDirectory: URL(fileURLWithPath: "/work/shop"),
      workspace: nil,
      lifeline: lifeline,
      runner: runner,
    )

    _ = try await caller.call(CallTool.Parameters(name: "use_cases_validate_files"))

    return await runner.invocations
  }

  @Test
  func `every command is handed the lifeline the server was given`() async throws {
    #expect(try await invocations(lifeline: 11).map(\.lifeline) == [11])
  }

  @Test
  func `a server with no lifeline hands none`() async throws {
    #expect(try await invocations(lifeline: nil).map(\.lifeline) == [nil])
  }
}
