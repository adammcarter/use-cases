import Foundation
import MCP
import Testing
@testable import UseCasesMCP

/// What the reader asks of the keeper of arguments it is given.
struct ToolFrameReaderHoldingTests {
  private func members(of data: Data) throws -> [String: Value] {
    try #require(JSONDecoder().decode(PlainJSON.self, from: data).value.objectValue)
  }

  @Test
  func `the arguments of a call are kept by the keeper it was given, and its key stands in`()
    async throws
  {
    let holder = SpyToolCallArgumentHolding(answering: "the-key")

    let swapped = try await members(
      of: ToolFrameReader(arguments: holder).frame(
        for: Data(
          """
          {"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"n",\
          "arguments":{"q":"data:,x"}}}
          """.utf8,
        ),
      ),
    )

    let parameters = try #require(swapped["params"]?.objectValue)
    #expect(parameters["arguments"] == [ToolCallArguments.keyMember: "the-key"])
    #expect(await holder.held == [["q": "data:,x"]])
  }
}
