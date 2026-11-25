import Foundation
import MCP
import Testing
@testable import UseCasesMCP

struct ToolFrameReaderTests {
  private let arguments = ToolCallArguments()

  private func frame(_ text: String) async -> Data {
    await ToolFrameReader(arguments: arguments).frame(for: Data(text.utf8))
  }

  private func members(of data: Data) throws -> [String: Value] {
    try #require(JSONDecoder().decode(PlainJSON.self, from: data).value.objectValue)
  }

  private static let call = """
  {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"use_cases_search",\
  "arguments":{"query":"data: rows, all","title":"data:,hello","n":3}}}
  """

  @Test
  func `the arguments of a call are set aside as written and a key stands in their place`(
  ) async throws {
    let swapped = try await members(of: frame(Self.call))
    let parameters = try #require(swapped["params"]?.objectValue)
    let standIn = try #require(parameters["arguments"]?.objectValue)

    #expect(Array(standIn.keys) == [ToolCallArguments.keyMember])
    #expect(
      await arguments.arguments(read: standIn) == [
        "query": .string("data: rows, all"),
        "title": .string("data:,hello"),
        "n": .int(3),
      ],
    )
  }

  @Test
  func `nothing else of the call changes: its id, method, name and metadata`() async throws {
    let swapped = try await members(
      of: frame(
        """
        {"jsonrpc":"2.0","id":"abc","method":"tools/call","params":{"_meta":{"progressToken":5},\
        "name":"use_cases_docs","arguments":{"query":"x"}}}
        """,
      ),
    )
    let parameters = try #require(swapped["params"]?.objectValue)

    #expect(swapped["id"] == "abc")
    #expect(swapped["jsonrpc"] == "2.0")
    #expect(swapped["method"] == "tools/call")
    #expect(parameters["name"] == "use_cases_docs")
    #expect(parameters["_meta"] == ["progressToken": 5])
  }

  @Test
  func `the arguments are given back once, and what is not a key is given as it was read`(
  ) async throws {
    let swapped = try await members(of: frame(Self.call))
    let standIn = try #require(swapped["params"]?.objectValue?["arguments"]?.objectValue)

    #expect(await arguments.arguments(read: standIn)?["query"] == "data: rows, all")
    #expect(await arguments.arguments(read: standIn) == standIn)
    #expect(await arguments.arguments(read: ["query": "x"]) == ["query": "x"])
    #expect(await arguments.arguments(read: nil) == nil)
    #expect(
      await arguments.arguments(read: [ToolCallArguments.keyMember: "not a key held"])
        == [ToolCallArguments.keyMember: "not a key held"],
    )
  }

  @Test
  func `every call of a batch is swapped, and what is not a call is left in it`() async throws {
    let firstCall = #"{"jsonrpc":"2.0","id":1,"method":"tools/call","#
      + #""params":{"name":"a","arguments":{"q":"data:,1"}}}"#
    let notification = #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#
    let thirdCall = #"{"jsonrpc":"2.0","id":2,"method":"tools/call","#
      + #""params":{"name":"b","arguments":{"q":"data:,2"}}}"#
    let batch = "[\(firstCall),\(notification),\(thirdCall)]"
    let swapped = try #require(
      await JSONDecoder().decode(PlainJSON.self, from: frame(batch)).value.arrayValue,
    )
    let first = try #require(swapped[0].objectValue?["params"]?.objectValue?["arguments"]?
      .objectValue)
    let third = try #require(swapped[2].objectValue?["params"]?.objectValue?["arguments"]?
      .objectValue)

    #expect(swapped.count == 3)
    #expect(Array(first.keys) == [ToolCallArguments.keyMember])
    #expect(Array(third.keys) == [ToolCallArguments.keyMember])
    #expect(swapped[1].objectValue?["method"] == "notifications/initialized")
    #expect(await arguments.arguments(read: first) == ["q": "data:,1"])
    #expect(await arguments.arguments(read: third) == ["q": "data:,2"])
  }

  @Test(arguments: [
    #"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"arguments":{"a":"data:,x"}}}"#,
    #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
    #"{"jsonrpc":"2.0","id":1,"result":{}}"#,
    #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"use_cases_docs"}}"#,
    #"{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"x","arguments":[1]}}"#,
    #"{"jsonrpc":"2.0","id":1,"method":"tools/call"}"#,
    "not json at all",
    "[]",
    "",
  ])
  func `a frame that holds no call with arguments is passed on exactly as it came`(
    text: String,
  ) async {
    #expect(await frame(text) == Data(text.utf8))
  }
}
