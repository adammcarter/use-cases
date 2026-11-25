import Testing
@testable import UseCasesCore

struct FreshnessPolicyTests {
  private func policy(_ json: String) throws -> FreshnessPolicy {
    try FreshnessPolicy(authored: AuthoredObject(authored(json), at: "freshness"))
  }

  @Test
  func `an empty freshness is the standard policy`() throws {
    #expect(try policy("{}") == .standard)
    #expect(FreshnessPolicy.standard.bindingIdentity == .content)
    #expect(FreshnessPolicy.standard.ignoring == [.lineEndings])
  }

  @Test(
    arguments: [
      "{}",
      #"{"binding_identity":"content"}"#,
      #"{"normalization":{}}"#,
    ],
  )
  func `an omitted normalization or ignore ignores line endings`(json: String) throws {
    #expect(try policy(json).ignoring == [.lineEndings])
  }

  @Test
  func `a written empty ignore is exact`() throws {
    let exact = try policy(#"{"normalization":{"ignore":[]}}"#)

    #expect(exact.ignoring.isEmpty)
    #expect(try exact != policy("{}"))
  }

  @Test
  func `both entries ignore both differences`() throws {
    let both = try policy(#"{"normalization":{"ignore":["line-endings","whitespace"]}}"#)

    #expect(both.ignoring == [.lineEndings, .whitespace])
  }

  @Test(
    arguments: [
      ("content", BindingIdentityMode.content),
      ("content-and-locator", BindingIdentityMode.contentAndLocator),
    ],
  )
  func `a binding identity is read`(
    case example: (text: String, mode: BindingIdentityMode),
  ) throws {
    let json = JSONMembers(["binding_identity": jsonString(example.text)]).json
    let policy = try policy(json)

    #expect(policy.bindingIdentity == example.mode)
  }

  @Test
  func `normalization names the differences to ignore, line endings first`() throws {
    let policy = try policy(
      #"{"normalization":{"ignore":["whitespace","line-endings"]}}"#,
    )

    #expect(policy.ignoring == [.lineEndings, .whitespace])
  }

  @Test(
    arguments: [
      #"["line-endings","whitespace"]"#,
      #"["whitespace","line-endings"]"#,
      #"["whitespace","line-endings","whitespace","line-endings"]"#,
    ],
  )
  func `equal settings in any order, or repeated, make equal policies`(list: String) throws {
    let written = try policy("{\"normalization\":{\"ignore\":" + list + "}}")
    let canonical = FreshnessPolicy(
      bindingIdentity: .content,
      ignoring: [.lineEndings, .whitespace],
    )

    #expect(written == canonical)
  }

  @Test
  func `the same rule given twice is held once`() {
    let policy = FreshnessPolicy(
      bindingIdentity: .content,
      ignoring: [.whitespace, .whitespace],
    )

    #expect(policy.ignoring == [.whitespace])
  }

  @Test(
    arguments: [
      #"{"binding_identity":"locator"}"#,
      #"{"normalization":{"ignore":["comments"]}}"#,
      #"{"normalization":{"ignore":["line-endings",3]}}"#,
    ],
  )
  func `a value the policy does not know is refused`(json: String) {
    #expect(throws: AuthoredShapeError.self) {
      try policy(json)
    }
  }

  @Test
  func `a refused normalization names the item`() {
    #expect(
      throws: AuthoredShapeError.unknownChoice(
        location: "freshness.normalization.ignore[1]",
        text: "comments",
      ),
    ) {
      try policy(#"{"normalization":{"ignore":["whitespace","comments"]}}"#)
    }
  }
}
