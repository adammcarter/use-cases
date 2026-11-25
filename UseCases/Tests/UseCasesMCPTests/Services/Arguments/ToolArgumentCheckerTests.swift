import MCP
import Testing
@testable import UseCasesMCP

struct ToolArgumentCheckerTests {
  private func checker(_ tool: ToolDefinition) throws -> ToolArgumentChecker {
    try ToolArgumentChecker(schema: tool.inputSchema)
  }

  @Test
  func `arguments that keep the schema have nothing to refuse`() throws {
    let checker = try checker(.verifyTests)

    #expect(checker.refusal(of: ["step": "run"]) == nil)
    #expect(checker.refusal(of: ["step": "run", "only": ["a", "b"], "workspace": "/w"]) == nil)
  }

  @Test
  func `a missing required argument is told as needs, by name`() throws {
    #expect(try checker(.verifyTests).refusal(of: [:]) == "needs step")
  }

  @Test
  func `every missing required argument is told`() throws {
    let refusal = try checker(.recordVerdict).refusal(of: ["route": "r"])

    #expect(refusal?.contains("needs use_case") == true)
    #expect(refusal?.contains("needs status") == true)
    #expect(refusal?.contains("needs route") == false)
  }

  @Test
  func `an argument the tool does not take is told as takes no, by name`() throws {
    let refusal = try checker(.verifyTests).refusal(of: ["step": "run", "shell": "rm -rf /"])

    #expect(refusal == "takes no shell")
  }

  @Test
  func `several arguments the tool does not take are told together`() throws {
    let refusal = try checker(.show).refusal(of: ["use_case": "a.b.c", "x": 1, "y": 2])

    #expect(refusal?.hasPrefix("takes no ") == true)
    #expect(refusal?.contains("x") == true)
    #expect(refusal?.contains("y") == true)
  }

  @Test(arguments: [
    ("only", Value.string("a")),
    ("only", .array([.string("a"), .int(2)])),
    ("workspace", .int(3)),
    ("run_id", .bool(true)),
    ("workspace", .null),
  ])
  func `a value of the wrong JSON type is told, where it is`(
    name: String,
    value: Value,
  ) throws {
    let refusal = try checker(.verifyTests).refusal(of: ["step": "run", name: value])

    #expect(refusal?.hasPrefix(name) == true)
    #expect(refusal?.contains("not of type") == true)
  }

  @Test
  func `a number with no fraction is an integer`() throws {
    #expect(try checker(.docs).refusal(of: ["page_size": .double(5.0)]) == nil)
    #expect(try checker(.docs).refusal(of: ["page_size": .double(5.5)]) != nil)
    #expect(try checker(.docs).refusal(of: ["page_size": .string("5")]) != nil)
  }

  @Test(arguments: ["walk", "", "--json", "RUN"])
  func `a step the tool does not list is left to the command line to refuse`(
    step: String,
  ) throws {
    #expect(try checker(.verifyTests).refusal(of: ["step": .string(step)]) == nil)
  }

  @Test
  func `a nested value is checked as deep as the schema goes, and no deeper`() throws {
    let checker = try checker(.save)

    #expect(checker.refusal(of: ["use_case": ["id": "a.b.c", "anything": [1, 2]]]) == nil)
    #expect(checker.refusal(of: ["use_case": "a.b.c"]) != nil)
  }

  @Test
  func `all that is wrong is told at once, in the order the checker finds it`() throws {
    let refusal = try checker(.verifyTests).refusal(of: ["only": "a", "shell": "x"])

    #expect(refusal?.contains("needs step") == true)
    #expect(refusal?.contains("takes no shell") == true)
    #expect(refusal?.contains("; ") == true)
  }

  @Test
  func `a schema the core's checker refuses is refused`() {
    #expect(throws: ToolArgumentCheckerError.self) {
      try ToolArgumentChecker(schema: ["type": "object", "examples": []])
    }
  }
}
