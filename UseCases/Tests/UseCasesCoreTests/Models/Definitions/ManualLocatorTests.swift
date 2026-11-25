import Testing
@testable import UseCasesCore

struct ManualLocatorTests {
  private func locator(_ json: String) throws -> ManualLocator {
    try ManualLocator(authored: AuthoredObject(authored(json), at: "locator"))
  }

  @Test
  func `a locator with only a file is a whole-file binding`() throws {
    let locator = try locator(#"{"file":"config/auth.yml"}"#)

    #expect(locator.file.text == "config/auth.yml")
    #expect(locator.range == nil)
  }

  @Test
  func `a start and an end make a range, the end column optional`() throws {
    let locator = try locator(
      #"{"file":"src/login.py","start":{"line":40},"end":{"line":78,"column":2}}"#,
    )
    let range = try #require(locator.range)

    #expect(range.start.line == 40)
    #expect(range.start.column == nil)
    #expect(range.end.line == 78)
    #expect(range.end.column == 2)
  }

  @Test
  func `a start without an end is refused, and an end without a start`() {
    #expect(throws: AuthoredShapeError.missing(location: "locator.end")) {
      try locator(#"{"file":"a","start":{"line":1}}"#)
    }
    #expect(throws: AuthoredShapeError.missing(location: "locator.start")) {
      try locator(#"{"file":"a","end":{"line":1}}"#)
    }
  }

  @Test(
    arguments: [
      #"{"file":"/etc/passwd"}"#,
      #"{"file":"../outside"}"#,
      #"{"file":"./src/a.js"}"#,
      #"{"file":"src/"}"#,
      #"{"file":"a\\b"}"#,
    ],
  )
  func `a file that is not a canonical workspace path is refused`(json: String) {
    #expect(throws: AuthoredShapeError.self) {
      try locator(json)
    }
  }
}
