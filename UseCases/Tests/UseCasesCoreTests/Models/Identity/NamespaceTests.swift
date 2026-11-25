import Testing
@testable import UseCasesCore

struct NamespaceTests {
  @Test(
    arguments: [
      ("app", 1),
      ("app.auth", 2),
      ("app.auth.login", 3),
      ("renderer.3d.preview", 3),
      ("legacy.v2.import", 3),
      ("a-b.c-d", 2),
      (Array(repeating: "seg", count: 1000).joined(separator: "."), 1000),
    ],
  )
  func `a namespace of valid segments is accepted and keeps its text`(
    text: String,
    count: Int,
  ) throws {
    let namespace = try Namespace(validating: text)

    #expect(namespace.segments.count == count)
    #expect(namespace.text == text)
  }

  @Test
  func `an empty namespace is refused`() {
    #expect(throws: IdentityError.empty) {
      try Namespace(validating: "")
    }
  }

  @Test(arguments: ["app..login", ".app.login", "app.login.", ".", "..", "a..b..c"])
  func `an empty piece between dots is refused`(text: String) {
    #expect(throws: IdentityError.emptySegment(within: text)) {
      try Namespace(validating: text)
    }
  }

  @Test(
    arguments: [
      ("App.Login", IdentityError.invalidCharacter("A", within: "App.Login")),
      ("app/auth/login", .invalidCharacter("/", within: "app/auth/login")),
      ("app.login\n", .invalidCharacter("\n", within: "app.login\n")),
      ("app.login\r\n", .invalidCharacter("\r", within: "app.login\r\n")),
      ("app.sign_in", .invalidCharacter("_", within: "app.sign_in")),
      ("app.-login", .leadingHyphen(within: "app.-login")),
      ("app-.login", .trailingHyphen(within: "app-.login")),
      ("app.login-", .trailingHyphen(within: "app.login-")),
    ],
  )
  func `a piece off the segment grammar is refused`(
    text: String,
    expected: IdentityError,
  ) {
    #expect(throws: expected) {
      try Namespace(validating: text)
    }
  }

  @Test
  func `a namespace followed by another keeps every segment in order`() throws {
    let scope = try Namespace(validating: "app.auth")
    let file = try Namespace(validating: "login.v2")

    #expect(scope.appending(file).text == "app.auth.login.v2")
  }

  @Test
  func `a namespace made of one segment`() throws {
    let scope = try Namespace(validating: "app")
    let segment = try IdentifierSegment(validating: "success")

    #expect(Namespace(segment).text == "success")
    #expect(scope.appending(Namespace(segment)).text == "app.success")
  }

  @Test
  func `two namespaces with the same text are equal and hash alike`() throws {
    let first = try Namespace(validating: "app.auth")
    let second = try Namespace(validating: "app.auth")

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }

  @Test
  func `the message names the whole id, not only the piece that failed`() {
    do {
      _ = try Namespace(validating: "App.Login")
      Issue.record("expected the namespace to be refused")
    } catch {
      #expect(error.description.hasPrefix("'App.Login' is not a valid id: "))
    }
  }
}
