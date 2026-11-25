import Testing
@testable import UseCasesCore

struct ResolvedLinkTests {
  @Test
  func `an implementation link has no route and its key is use case, binding, file and line`()
    throws
  {
    let link = try ResolvedLink.sample(
      binding: "authenticate-request",
      file: "src/login.swift",
      lines: 40 ... 78,
    )

    #expect(link.role == .implementation)
    #expect(link.route == nil)
    #expect(link.key == "app.toggle#authenticate-request@src/login.swift:40")
    #expect(link.startLine == 40)
    #expect(link.endLine == 78)
  }

  @Test
  func `a link under a route is a validation link and the route is in its key`() throws {
    let link = try ResolvedLink.sample(
      useCase: "shop.login.authenticate",
      route: "unit-tests",
      binding: "valid-credentials",
      file: "Tests/AuthTests/LoginTests.swift",
      lines: 6 ... 9,
    )

    #expect(link.role == .validation)
    #expect(link.route == "unit-tests")
    #expect(
      link.key
        ==
        "shop.login.authenticate#unit-tests.valid-credentials@Tests/AuthTests/LoginTests.swift:6",
    )
  }

  @Test(arguments: ["My Tests/add test.test.js", "tests/café.test.js", "tests/a@b:c.test.js"])
  func `the file in a key is the path exactly as spelled`(file: String) throws {
    let link = try ResolvedLink.sample(
      route: "unit-tests",
      binding: "adds",
      file: file,
      lines: 5 ... 5,
    )

    #expect(link.key == "app.toggle#unit-tests.adds@\(file):5")
  }

  @Test
  func `a link records where it came from`() throws {
    #expect(try ResolvedLink.sample(source: .marker).source == .marker)
    #expect(try ResolvedLink.sample(source: .manual).source == .manual)
  }
}
