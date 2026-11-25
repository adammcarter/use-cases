import Testing
@testable import UseCasesCore

struct IdentifierSegmentTests {
  @Test(
    arguments: [
      "a", "0", "login", "sign-in", "oauth2", "ipv6", "3d", "v2", "a-b-c", "a--b", "0-0",
      "invalid-password", "full-app-acceptance", String(repeating: "a", count: 10000),
    ],
  )
  func `a segment on the grammar is accepted as written`(text: String) throws {
    let segment = try IdentifierSegment(validating: text)

    #expect(segment.text == text)
    #expect(segment.description == text)
  }

  @Test
  func `an empty segment is refused`() {
    #expect(throws: IdentityError.empty) {
      try IdentifierSegment(validating: "")
    }
  }

  @Test(
    arguments: [
      ("-", IdentityError.leadingHyphen(within: "-")),
      ("-signin", .leadingHyphen(within: "-signin")),
      ("-a-", .leadingHyphen(within: "-a-")),
      ("signin-", .trailingHyphen(within: "signin-")),
      ("a-", .trailingHyphen(within: "a-")),
      (
        "a" + String(repeating: "b", count: 10000) + "-",
        .trailingHyphen(within: "a" + String(repeating: "b", count: 10000) + "-"),
      ),
    ],
  )
  func `a segment beginning or ending with a hyphen is refused`(
    text: String,
    expected: IdentityError,
  ) {
    #expect(throws: expected) {
      try IdentifierSegment(validating: text)
    }
  }

  @Test(
    arguments: [
      ("Login", Unicode.Scalar("L")),
      ("sign_in", "_"),
      ("sign in", " "),
      (" ", " "),
      ("a.b", "."),
      ("a/b", "/"),
      ("a#b", "#"),
      ("\u{E9}", "\u{E9}"),
      ("cafe\u{301}", "\u{301}"),
      ("\u{FF41}", "\u{FF41}"),
      ("\u{663}", "\u{663}"),
      ("a\u{0}", "\u{0}"),
      ("a\n", "\n"),
      ("\n", "\n"),
      ("a\r\n", "\r"),
      ("a\u{2028}", "\u{2028}"),
    ],
  )
  func `a character off the grammar is refused, a line break included`(
    text: String,
    offender: Unicode.Scalar,
  ) {
    #expect(throws: IdentityError.invalidCharacter(offender, within: text)) {
      try IdentifierSegment(validating: text)
    }
  }

  @Test
  func `two segments with the same text are equal and hash alike`() throws {
    let first = try IdentifierSegment(validating: "login")
    let second = try IdentifierSegment(validating: "login")

    #expect(first == second)
    #expect(Set([first, second]).count == 1)
  }
}
