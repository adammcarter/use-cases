import Testing
@testable import UseCasesCore

/// A semantic hash is written into evidence ledgers and compared across runs, so
/// every digest below is the EXACT value `computeSemanticHash` returns in
/// TypeScript today. A changed digest is a broken contract, not a refactor.
struct SemanticHashTests {
  @Test(arguments: [
    (JSONValue.null, "sha256:74234e98afe7498fb5daf1f36ac2d78acc339464f950703b8c019892f982b90b"),
    (
      JSONValue.bool(true),
      "sha256:b5bea41b6c623f7c09f1bf24dcae58ebab3c0cdd90ad966bc43a45b44867e12b"
    ),
    (
      JSONValue.number(1),
      "sha256:6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b"
    ),
    (
      JSONValue.number(1.5),
      "sha256:9f29a130438b81170b92a42650f9a94291ecad60bd47af2a3886e75f7f728725"
    ),
    (
      JSONValue.number(1e21),
      "sha256:241c4643fa70b1dcde1205b71be4e3bebb17e9f880c8e1a33d0ead6c27271d3c"
    ),
    (
      JSONValue.number(-0.0),
      "sha256:5feceb66ffc86f38d952786c6d696c79c2dbc239dd4e91b46729d73a27fb57e9"
    ),
    (
      JSONValue.number(1e-7),
      "sha256:5b33e02f2c5103a05d32f6ba9cb058294452bfbf393967f68bb30c1bdcbbab22"
    ),
    (
      JSONValue.number(0.1 + 0.2),
      "sha256:06bad31060c1212ae832de4c031f7b31e3b48aed57858294478cb19450cf34ca"
    ),
    (
      JSONValue.string(""),
      "sha256:12ae32cb1ec02d01eda3581b127c1fee3b0dc53572ed6baf239721a03d82e126"
    ),
    (
      JSONValue.string("é😀"),
      "sha256:5120b0dbdd5539f03b48389a6740c87aa497758ca96b3d69165453c9e01f3235"
    ),
    (
      JSONValue.string("a\"b\\c\nd\te\u{1}"),
      "sha256:23fddd1f0bfd8eeeee4d6d09bfea9e25d890f0a2d7bb72302e99961409138804"
    ),
    (
      JSONValue.array([]),
      "sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945"
    ),
    (
      JSONValue.object(JSONObject()),
      "sha256:44136fa355b3678a1146ad16f7e8649e94fb4fc21fe77e8310c060f61caaff8a"
    ),
  ])
  func `hashes a value to the digest the TypeScript produced`(
    value: JSONValue,
    expected: String,
  ) {
    #expect(SemanticHash.compute(value) == expected)
  }

  @Test
  func `hashes a sorted object to its frozen digest`() {
    let value = JSONValue.object(JSONObject([
      ("zebra", .number(1)), ("alpha", .number(2)), ("Beta", .number(3)),
    ]))

    #expect(
      SemanticHash.compute(value)
        == "sha256:8a6a69207527d39b904cbd7ba036df851d8e29ea3334fc5caa6304b25fdd850d",
    )
  }

  @Test
  func `hashes a use-case row to its frozen digest`() {
    let value = JSONValue.object(JSONObject([
      ("id", .string("checkout.apply_coupon")),
      ("title", .string("Apply a coupon")),
      ("lifecycle", .string("active")),
      ("value_tier", .string("core")),
      ("observable_outcomes", .array([.string("discount applied"), .string("total updated")])),
      ("scenarios", .array([.object(JSONObject([
        ("id", .string("s.one")),
        ("kind", .string("steps")),
        ("steps", .array([.string("open"), .string("apply")])),
      ]))])),
    ]))

    #expect(
      SemanticHash.compute(value)
        == "sha256:2156776e8a5fbd173a5667caeff8320ace0e224774474c21e2da422f362541a4",
    )
  }

  @Test
  func `key order in the document does not change the digest`() {
    let left = JSONValue.object(JSONObject([("a", .number(1)), ("b", .number(2))]))
    let right = JSONValue.object(JSONObject([("b", .number(2)), ("a", .number(1))]))

    #expect(SemanticHash.compute(left) == SemanticHash.compute(right))
  }

  @Test
  func `a changed value changes the digest`() {
    let left = JSONValue.object(JSONObject([("a", .number(1))]))
    let right = JSONValue.object(JSONObject([("a", .number(2))]))

    #expect(SemanticHash.compute(left) != SemanticHash.compute(right))
  }

  @Test
  func `every digest carries the sha256 prefix and sixty four hex characters`() {
    let digest = SemanticHash.compute(.string("anything"))
    let hexadecimal = digest.dropFirst("sha256:".count)

    #expect(digest.hasPrefix("sha256:"))
    #expect(hexadecimal.count == 64)
    #expect(hexadecimal.allSatisfy { $0.isHexDigit && !$0.isUppercase })
  }
}
