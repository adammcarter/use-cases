@testable import UseCasesTransformers

/// A workspace with one XCTest file and a `swift test` report folder.
enum XCTestWorkspace {
  static let source = """
  import XCTest

  final class LoginTests: XCTestCase {
    func testValid() {
      XCTAssert(true)
    }

    func testBad() {
      XCTAssert(false)
    }
  }
  """

  static func respond(
    console: String?,
    events: String?,
    links: [RequestLink],
    source: String = XCTestWorkspace.source,
  ) throws -> ResultsResponse {
    let workspace = try ResultsWorkspace()

    try workspace.folder.write(
      "Tests/ShopTests/LoginTests.swift",
      source,
    )

    if let console {
      try workspace.writeReportFile(
        "console.txt",
        console,
      )
    }

    if let events {
      try workspace.writeReportFile(
        "events.jsonl",
        events,
      )
    }

    return try SwiftTestTransformer().results(for: workspace.request(links: links))
  }
}
