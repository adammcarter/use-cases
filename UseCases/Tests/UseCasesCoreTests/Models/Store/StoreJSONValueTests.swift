import Testing
@testable import UseCasesCore

struct StoreJSONValueTests {
  @Test
  func `members of an object keep the pairs they were given`() {
    let value = StoreJSONValue.members([
      "b": .integer(1),
      "a": .string("x"),
    ])

    #expect(
      value == .object([
        StoreJSONMember(key: "b", value: .integer(1)),
        StoreJSONMember(key: "a", value: .string("x")),
      ]),
    )
  }

  @Test
  func `a field that is nil is left out, never written as null`() {
    let value = StoreJSONValue.present([
      "kept": .string("x"),
      "left": nil,
      "null": .null,
    ])

    #expect(
      value == .object([
        StoreJSONMember(key: "kept", value: .string("x")),
        StoreJSONMember(key: "null", value: .null),
      ]),
    )
  }

  @Test
  func `strings become an array of strings in order`() {
    #expect(StoreJSONValue.strings(["b", "a"]) == .array([.string("b"), .string("a")]))
    #expect(StoreJSONValue.strings([]) == .array([]))
  }
}
