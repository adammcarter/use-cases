import Testing
@testable import UseCasesTransformers

struct SwiftTestTransformerLocatingTests {
  @Test
  func `a method declared twice in the class files is left unlinked with a note`() throws {
    let response = try XCTestWorkspace.respond(
      console: "Test Case '-[ShopTests.LoginTests testValid]' passed (0.001 seconds).\n",
      events: nil,
      links: [.validation(
        "Tests/ShopTests/LoginTests.swift",
        1,
        20,
      )],
      source: """
      final class LoginTests {
        func testValid() {
        }
        func testValid() {
        }
      }
      """,
    )

    #expect(response.results.isEmpty)
    #expect(response.diagnostics
      .contains("XCTest ShopTests.LoginTests.testValid is declared more than once; left unlinked"))
  }

  @Test
  func `a test that is not in any test file is unlinked`() throws {
    let response = try XCTestWorkspace.respond(
      console: "Test Case '-[ShopTests.LoginTests testGone]' passed (0.001 seconds).\n",
      events: nil,
      links: [.validation(
        "Tests/ShopTests/LoginTests.swift",
        1,
        20,
      )],
    )

    #expect(response.unlinked.count == 1)
  }

  @Test
  func `a class of the same name in another module is another test`() throws {
    let workspace = try ResultsWorkspace()
    let moduleA = RequestLink.validation(
      "Tests/ATests/FooTests.swift",
      1,
      9,
      binding: "a",
    )
    let moduleB = RequestLink.validation(
      "Tests/BTests/FooTests.swift",
      1,
      9,
      binding: "b",
    )
    let source = """
    final class FooTests {
      func testA() {
      }
    }
    """

    try workspace.folder.write(
      "Tests/ATests/FooTests.swift",
      source,
    )
    try workspace.folder.write(
      "Tests/BTests/FooTests.swift",
      source,
    )
    try workspace.writeReportFile(
      "console.txt",
      """
      Test Case '-[ATests.FooTests testA]' failed (0.1 seconds).
      Test Case '-[BTests.FooTests testA]' passed (0.1 seconds).
      """,
    )

    let response = try SwiftTestTransformer().results(
      for: workspace.request(links: [moduleA, moduleB]),
    )

    #expect(response.status(of: moduleA) == .fail)
    #expect(response.status(of: moduleB) == .pass)
  }

  @Test
  func `a class only a longer class name starts is not the class`() throws {
    let link = RequestLink.validation(
      "Tests/ShopTests/LoginTests.swift",
      1,
      20,
    )

    let response = try XCTestWorkspace.respond(
      console: "Test Case '-[ShopTests.LoginTests testValid]' passed (0.001 seconds).\n",
      events: nil,
      links: [link],
      source: """
      final class LoginTestsExtra {
        func testValid() {
        }
      }
      """,
    )

    #expect(response.status(of: link) == nil)
    #expect(response.unlinked.first?.file == nil)
  }

  @Test
  func `a class name that ends the line is the class`() throws {
    let link = RequestLink.validation(
      "Tests/ShopTests/LoginTests.swift",
      1,
      20,
    )

    let response = try XCTestWorkspace.respond(
      console: "Test Case '-[ShopTests.LoginTests testValid]' passed (0.001 seconds).\n",
      events: nil,
      links: [link],
      source: """
      final class LoginTests
      {
        func testValid() {
        }
      }
      """,
    )

    #expect(response.status(of: link) == .pass)
  }

  @Test
  func `one stray byte in the console does not garble the names around it`() throws {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "Tests/ShopTests/UmlautTests.swift",
      1,
      9,
    )
    let console = Array("Test Case '-[ShopTests.UmlautTests testÄ]' failed (0.1 seconds).\n".utf8)
      + [0xFF, 0x0A]

    try workspace.folder.write(
      "Tests/ShopTests/UmlautTests.swift",
      """
      final class UmlautTests {
        func testÄ() {
        }
      }
      """,
    )
    try workspace.folder.writeBytes(
      ResultsWorkspace.reportName + "/console.txt",
      console,
    )

    let response = try SwiftTestTransformer().results(for: workspace.request(links: [link]))

    #expect(response.status(of: link) == .fail)
  }

  @Test
  func `tests are searched for under the folder swift test ran in`() throws {
    let workspace = try ResultsWorkspace()
    let link = RequestLink.validation(
      "pkg/Tests/ShopTests/LoginTests.swift",
      1,
      9,
    )

    try workspace.folder.write(
      "pkg/Tests/ShopTests/LoginTests.swift",
      """
      final class LoginTests {
        func testValid() {
        }
      }
      """,
    )
    try workspace.writeReportFile(
      "console.txt",
      "Test Case '-[ShopTests.LoginTests testValid]' failed (0.1 seconds).\n",
    )

    let fromWorkingFolder = try SwiftTestTransformer().results(
      for: workspace.request(
        links: [link],
        workingDirectory: "pkg",
      ),
    )
    let fromRoot = try SwiftTestTransformer().results(for: workspace.request(links: [link]))

    #expect(fromWorkingFolder.status(of: link) == .fail)
    #expect(fromRoot.status(of: link) == nil)
  }

  @Test
  func `a console line holding a line separator does not hide a result`() throws {
    let link = RequestLink.validation(
      "Tests/ShopTests/LoginTests.swift",
      1,
      20,
    )

    let response = try XCTestWorkspace.respond(
      console: "noise \u{2028} noise \u{85}\n"
        + "Test Case '-[ShopTests.LoginTests testValid]' failed (0.1 seconds).\n",
      events: nil,
      links: [link],
    )

    #expect(response.status(of: link) == .fail)
  }
}
