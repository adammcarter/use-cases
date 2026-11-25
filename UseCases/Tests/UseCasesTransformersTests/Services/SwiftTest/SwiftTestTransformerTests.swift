import Testing
@testable import UseCasesTransformers

struct SwiftTestTransformerTests {
  private typealias Stream = SwiftTestingStream

  @Test
  func `XCTest results come from the console and are placed by their declaration`() throws {
    let valid = RequestLink.validation(
      "Tests/ShopTests/LoginTests.swift",
      4,
      6,
      binding: "valid",
    )
    let bad = RequestLink.validation(
      "Tests/ShopTests/LoginTests.swift",
      8,
      10,
      binding: "bad",
    )

    let response = try XCTestWorkspace.respond(
      console: """
      Test Case '-[ShopTests.LoginTests testValid]' passed (0.001 seconds).
      Test Case '-[ShopTests.LoginTests testBad]' failed (0.001 seconds).
      """,
      events: nil,
      links: [valid, bad],
    )

    #expect(response.status(of: valid) == .pass)
    #expect(response.status(of: bad) == .fail)
    #expect(response
      .diagnostics == ["no events.jsonl in the report: Swift Testing results unavailable"])
  }

  @Test
  func `both frameworks in one report are read`() throws {
    let workspace = try ResultsWorkspace()
    let xctest = RequestLink.validation(
      "Tests/ShopTests/LoginTests.swift",
      4,
      6,
      binding: "x",
    )
    let modern = RequestLink.validation(
      "Tests/ShopTests/ModernTests.swift",
      1,
      9,
      binding: "m",
    )

    try workspace.folder.write(
      "Tests/ShopTests/LoginTests.swift",
      XCTestWorkspace.source,
    )
    try workspace.writeReportFile(
      "console.txt",
      "Test Case '-[ShopTests.LoginTests testValid]' passed (0.001 seconds).\n",
    )
    try workspace.writeReportFile(
      "events.jsonl",
      Stream.stream(
        Stream.test(
          "M.t()",
          file: workspace.folder.absolute("Tests/ShopTests/ModernTests.swift"),
          line: 3,
        ),
        Stream.issue(
          "M.t()",
          isKnown: false,
        ),
        Stream.ended("M.t()"),
      ),
    )

    let response = try SwiftTestTransformer().results(for: workspace.request(links: [
      xctest,
      modern,
    ]))

    #expect(response.status(of: xctest) == .pass)
    #expect(response.status(of: modern) == .fail)
    #expect(response.diagnostics.isEmpty)
  }

  @Test
  func `each missing half of the report is named`() throws {
    let workspace = try ResultsWorkspace()

    try workspace.folder.write(
      ResultsWorkspace.reportName + "/.keep",
      "",
    )

    let response = try SwiftTestTransformer().results(for: workspace.request(links: []))

    #expect(
      response.diagnostics == [
        "no events.jsonl in the report: Swift Testing results unavailable",
        "no console.txt in the report: XCTest results unavailable",
      ],
    )
  }

  @Test
  func `a class is found only in a file declaring that class`() throws {
    let response = try XCTestWorkspace.respond(
      console: "Test Case '-[ShopTests.LoginTestsExtra testValid]' passed (0.001 seconds).\n",
      events: nil,
      links: [.validation(
        "Tests/ShopTests/LoginTests.swift",
        1,
        20,
      )],
    )

    #expect(response.results.isEmpty)
    #expect(response.unlinked.map(\.test) == ["ShopTests.LoginTestsExtra.testValid"])
    #expect(response.unlinked.first?.file == nil)
  }

  @Test
  func `a damaged event stream is a failure`() throws {
    let workspace = try ResultsWorkspace()

    try workspace.writeReportFile(
      "events.jsonl",
      "nonsense\n",
    )

    #expect(throws: TransformerFailure.self) {
      try SwiftTestTransformer().results(for: workspace.request(links: []))
    }
  }
}
