import Testing
@testable import UseCasesCore

struct RouteFingerprintComputerPolicyTests {
  @Test
  func `LF and CRLF checkouts of the same code agree by default`() throws {
    let unix = try fixture(root: FreshnessSamples.root(), body: "draw()\nfade()")
    let crlf = try fixture(root: FreshnessSamples.root(), body: "draw()\r\nfade()")

    #expect(try unix.fingerprint() == crlf.fingerprint())
  }

  @Test
  func `LF and CRLF checkouts differ when nothing is ignored`() throws {
    let root = FreshnessSamples.root(ignore: "[]")
    let unix = try fixture(root: root, body: "draw()\nfade()")
    let crlf = try fixture(root: root, body: "draw()\r\nfade()")

    #expect(try unix.fingerprint() != crlf.fingerprint())
  }

  @Test
  func `whitespace matters unless the policy ignores it`() throws {
    let tight = FreshnessSamples.root(ignore: "[line-endings, whitespace]")
    let spacedTight = try fixture(root: tight, body: "draw( )")
    let plainTight = try fixture(root: tight, body: "draw()")
    let strict = FreshnessSamples.root()
    let spacedStrict = try fixture(root: strict, body: "draw( )")
    let plainStrict = try fixture(root: strict, body: "draw()")

    #expect(try spacedTight.fingerprint() == plainTight.fingerprint())
    #expect(try spacedStrict.fingerprint() != plainStrict.fingerprint())
  }

  @Test
  func `content mode ignores a moved region`() throws {
    let root = FreshnessSamples.root(bindingIdentity: "content")
    let before = try fixture(root: root, body: "draw()", padding: "")
    let after = try fixture(root: root, body: "draw()", padding: "// moved down\n")

    #expect(try before.fingerprint() == after.fingerprint())
  }

  @Test
  func `content-and-locator does not`() throws {
    let root = FreshnessSamples.root(bindingIdentity: "content-and-locator")
    let before = try fixture(root: root, body: "draw()", padding: "")
    let after = try fixture(root: root, body: "draw()", padding: "// moved down\n")

    #expect(try before.fingerprint() != after.fingerprint())
  }

  @Test
  func `content mode ignores a region moved to another file`() throws {
    let root = FreshnessSamples.root()
    let before = try fixture(root: root, body: "draw()", file: "src/a.swift")
    let after = try fixture(root: root, body: "draw()", file: "src/b.swift")

    #expect(try before.fingerprint() == after.fingerprint())
  }

  @Test
  func `the policy is part of every fingerprint`() throws {
    let content = try fixture(root: FreshnessSamples.root(), body: "draw()")
    let locator = try fixture(
      root: FreshnessSamples.root(bindingIdentity: "content-and-locator"),
      body: "draw()",
    )

    #expect(try content.fingerprint() != locator.fingerprint())
  }

  @Test
  func `a changed body changes the fingerprint`() throws {
    let before = try fixture(root: FreshnessSamples.root(), body: "draw()")
    let after = try fixture(root: FreshnessSamples.root(), body: "draw(1)")

    #expect(try before.fingerprint() != after.fingerprint())
  }

  /// A workspace with one implementation marker around `body`.
  private func fixture(
    root: String,
    body: String,
    padding: String = "",
    file: String = "src/app.swift",
  ) throws -> FreshnessFixture {
    let fixture = try FreshnessFixture(root: root)
    try fixture.write(file, padding + LinkSamples.marked("app.toggle#draw", body))

    return fixture
  }
}
