import MCP
import Testing
@testable import UseCasesMCP

struct ToolInputSchemaTests {
  private func property(
    _ name: String,
    of tool: ToolDefinition,
  ) -> [String: Value]? {
    tool.inputSchema.objectValue?["properties"]?.objectValue?[name]?.objectValue
  }

  private func values(of schema: [String: Value]?) -> [String]? {
    schema?["enum"]?.arrayValue?.compactMap(\.stringValue)
  }

  @Test
  func `a list of states says which states its items take`() {
    let states = ["failed", "error", "incomplete", "unverified", "stale", "verified", "draft"]

    for tool in [ToolDefinition.status, .search] {
      let items = property("state", of: tool)?["items"]?.objectValue

      #expect(items?["type"] == "string")
      #expect(values(of: items) == states)
      #expect(property("state", of: tool)?["enum"] == nil)
    }
  }

  @Test
  func `the value tiers and the fields searched say which values they take`() {
    #expect(
      values(of: property("tier", of: .search)?["items"]?.objectValue)
        == ["critical", "core", "supporting"],
    )
    #expect(
      values(of: property("in", of: .search)?["items"]?.objectValue)
        == ["id", "title", "description", "intent", "scenarios", "out_of_scope", "validation"],
    )
  }

  @Test
  func `a page size is a whole number from 1 to 100`() {
    for tool in [ToolDefinition.search, .docs] {
      let size = property("page_size", of: tool)

      #expect(size?["type"] == "integer")
      #expect(size?["minimum"] == 1)
      #expect(size?["maximum"] == 100)
    }
  }

  @Test
  func `a list that names no values has items of a type only`() {
    #expect(
      property("only", of: .verifyTests)?["items"]
        == .object(["type": .string("string")]),
    )
  }

  @Test
  func `a string that names its values lists them as before`() {
    #expect(values(of: property("status", of: .recordVerdict)) == [
      "pass",
      "fail",
      "incomplete",
      "error",
    ])
  }

  @Test
  func `the range and the values are for the command to refuse, in its own words`() throws {
    let search = try ToolArgumentChecker(schema: ToolDefinition.search.inputSchema)

    #expect(search.refusal(of: ["query": "x", "page_size": 0]) == nil)
    #expect(search.refusal(of: ["query": "x", "page_size": 101]) == nil)
    #expect(search.refusal(of: ["query": "x", "state": ["nope"]]) == nil)
    #expect(search.refusal(of: ["query": "x", "tier": ["nope"]]) == nil)
    #expect(search.refusal(of: ["query": "x", "in": ["nope"]]) == nil)
    #expect(search.refusal(of: ["query": "x", "page_size": 1.5]) != nil)
  }
}
