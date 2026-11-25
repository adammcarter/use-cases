import Testing
@testable import UseCasesCore

struct SearchTokenCodecTests {
  private let codec = SearchTokenCodec()

  private static let parameters = StoreJSONValue.members([
    "words": .strings(["double", "tap"]),
    "offset": .integer(20),
    "text": .string("naïve ÿ ~~~ ??? 日本"),
  ])

  @Test
  func `a token reads back as the parameters it was made from`() throws {
    let token = codec.token(for: Self.parameters)
    let back = try codec.parameters(in: token)

    #expect(back == AuthoredValue.object([
      AuthoredMember(key: "offset", value: .integer(20)),
      AuthoredMember(key: "text", value: .string("naïve ÿ ~~~ ??? 日本")),
      AuthoredMember(key: "words", value: .array([.string("double"), .string("tap")])),
    ]))
  }

  @Test
  func `the same parameters give the same token`() {
    #expect(codec.token(for: Self.parameters) == codec.token(for: Self.parameters))
  }

  @Test
  func `a token holds only letters, digits, hyphens and underscores and begins with a letter`() {
    let token = codec.token(for: Self.parameters)

    #expect(token.utf8.allSatisfy { byte in
      (byte >= 48 && byte <= 57) || (byte >= 65 && byte <= 90) || (byte >= 97 && byte <= 122)
        || byte == 45 || byte == 95
    })
    #expect(token.first?.isLetter == true)
  }

  @Test(arguments: [
    "", "garbage", "eyJ2IjoyfQ==", "ey Jv", "ew+/", "!!!!", "eyJ2IjoyfQe", "AAAA", "ZXhhbXBsZQ",
  ])
  func `text that is not a token is refused`(token: String) {
    #expect(throws: SearchTokenError.malformed) {
      try codec.parameters(in: token)
    }
  }
}
