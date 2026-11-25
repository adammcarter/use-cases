import Testing
@testable import UseCasesCore

struct IdentifierGlobTests {
  private func matches(
    _ glob: String,
    _ identifier: String,
  ) throws -> Bool {
    try IdentifierGlob(validating: glob).matches(UseCaseIdentifier(validating: identifier))
  }

  @Test(arguments: [
    ("app.*.success", "app.login.success", true),
    ("app.*.success", "app.checkout.success", true),
    ("app.*.success", "app.success", false),
    ("app.*.success", "app.auth.login.success", false),
    ("**.success", "app.login.success", true),
    ("**.success", "success", true),
    ("**.success", "app.login.lockout", false),
    ("app.**", "app", true),
    ("app.**", "app.login.success", true),
    ("app.**", "application", false),
    ("app.**.success", "app.success", true),
    ("app.**.success", "app.a.b.c.success", true),
    ("*", "app", true),
    ("*", "app.login", false),
    ("**", "app.login", true),
    ("app.login", "app.login", true),
    ("app.login", "app.login.success", false),
  ])
  func `a glob matches whole segments only`(
    glob: String,
    identifier: String,
    expected: Bool,
  ) throws {
    #expect(try matches(glob, identifier) == expected)
  }

  @Test(arguments: [
    "", "app..login", ".app", "app.", "app.log*", "app.*login", "app.**foo", "App.*", "app.-x",
    "app.x-", "app.a b", "app.*\n",
  ])
  func `a glob that is not whole segments is refused`(text: String) {
    #expect(throws: IdentityError.self) {
      try IdentifierGlob(validating: text)
    }
  }

  @Test
  func `a glob is written back as it was read`() throws {
    #expect(try IdentifierGlob(validating: "app.**.*.success").text == "app.**.*.success")
  }

  // MARK: - A glob of any length is matched in the time its length takes

  // Nothing is timed and no test carries a time limit: a hang shows as a run that does not end, and
  // what is checked is the answer.

  @Test
  func `ten thousand double stars match as one, however long the id`() throws {
    let glob = try IdentifierGlob(
      validating: Array(repeating: "**", count: 10000).joined(separator: ".") + ".success",
    )

    #expect(glob.segments.count == 2)
    #expect(try glob.matches(UseCaseIdentifier(validating: "app.login.success")))
    #expect(try !glob.matches(UseCaseIdentifier(validating: "app.login.lockout")))
  }

  @Test
  func `a long glob that cannot be merged is still matched without recursing`() throws {
    let pieces = (0 ..< 5000).flatMap { _ in
      ["**", "a"]
    }
    let glob = try IdentifierGlob(validating: pieces.joined(separator: "."))
    let identifier = Array(repeating: "a", count: 5000).joined(separator: ".")

    #expect(glob.segments.count == 10000)
    #expect(try glob.matches(UseCaseIdentifier(validating: identifier)))
    #expect(try !glob.matches(UseCaseIdentifier(validating: identifier + ".b")))
  }

  @Test
  func `a glob keeps the text it was written with, even when its stars are merged`() throws {
    #expect(try IdentifierGlob(validating: "app.**.**.success").text == "app.**.**.success")
    #expect(try IdentifierGlob(validating: "app.**.**.success").segments.count == 3)
  }
}
