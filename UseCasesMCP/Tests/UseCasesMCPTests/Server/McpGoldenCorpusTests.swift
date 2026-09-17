import Foundation
import Testing
import TestSupport
import UseCasesCore
@testable import UseCasesMCP

/// Every recorded TypeScript exchange, replayed through the Swift server and
/// compared byte for byte: the response line, the files the run left behind,
/// and the whole sandbox listing — so a read that wrote something would fail.
struct McpGoldenCorpusTests {
  @Test(arguments: McpGoldenCorpus.caseNames)
  func `reproduces the TypeScript MCP server byte for byte`(caseName: String) async throws {
    let recorded = try McpCorpusFixtures.testCase(caseName)
    let sandbox = try McpCorpusFixtures.Sandbox(recorded: recorded)
    let server = McpStdioServer(environment: sandbox.environment)
    let expected = sandbox.responses
    let requests = sandbox.requests
    try #require(requests.count == expected.count)

    for (index, line) in requests.enumerated() {
      let response = await server.response(to: Data(line.utf8))
      let produced = response.map { answer in
        McpCorpusNormalisation.applied(
          to: sandbox.withPlaceholder(answer.jsonText),
          clockFields: sandbox.clockFields,
        )
      }
      #expect(produced == expected[index], "request \(index) of \(caseName)")
    }

    for entry in sandbox.filesAfter {
      let contents = sandbox.contents(of: entry.path).map { text in
        McpCorpusNormalisation.applied(
          to: sandbox.withPlaceholder(text),
          clockFields: sandbox.clockFields,
        )
      }
      #expect(contents == entry.contents, "\(entry.path) after \(caseName)")
    }
    let listing = sandbox.listing().map { entry in
      McpCorpusNormalisation.applied(to: entry)
    }
    #expect(listing == sandbox.expectedListing)
  }
}
