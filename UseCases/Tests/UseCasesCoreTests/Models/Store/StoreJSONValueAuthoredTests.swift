import Testing
@testable import UseCasesCore

struct StoreJSONValueAuthoredTests {
  private let writer = StoreJSONWriter()

  @Test(
    arguments: [
      (AuthoredValue.string("x"), StoreJSONValue.string("x")),
      (.integer(3), .integer(3)),
      (.number(1.5), .number(1.5)),
      (.boolean(true), .boolean(true)),
      (.boolean(false), .boolean(false)),
      (.null, .null),
      (.array([.integer(1), .string("a")]), .array([.integer(1), .string("a")])),
      (.array([]), .array([])),
      (.object([]), .object([])),
    ],
  )
  func `every authored value becomes the same JSON value`(
    authored: AuthoredValue,
    json: StoreJSONValue,
  ) {
    #expect(StoreJSONValue(authored) == json)
  }

  @Test
  func `an object keeps its members and nests`() {
    let authored = AuthoredValue.object([
      AuthoredMember(key: "files", value: .string("test/**/*.js")),
      AuthoredMember(
        key: "flags",
        value: .object([
          AuthoredMember(key: "strict", value: .boolean(true)),
          AuthoredMember(key: "limit", value: .integer(5)),
          AuthoredMember(key: "none", value: .null),
        ]),
      ),
    ])

    #expect(
      writer.compact(StoreJSONValue(authored)).utf8Text
        == #"{"files":"test/**/*.js","flags":{"limit":5,"none":null,"strict":true}}"#,
    )
  }
}
