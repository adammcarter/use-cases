import Testing
@testable import UseCasesCore

struct AuthoredValueByteOrderMarkTests {
  @Test(arguments: [
    AuthoredValue.string("\u{FEFF}x"),
    .string("\u{FEFF}"),
    .array([.string("a"), .string("\u{FEFF}b")]),
    .members(["\u{FEFF}k": .integer(1)]),
    .members(["a": .array([.members(["b": .string("\u{FEFF}c")])])]),
  ])
  func `text, or a key, that starts with a byte order mark is found anywhere in a value`(
    value: AuthoredValue,
  ) {
    #expect(value.hasTextStartingWithByteOrderMark)
  }

  @Test(arguments: [
    AuthoredValue.string("x\u{FEFF}"),
    .string(" \u{FEFF}"),
    .string(""),
    .null,
    .integer(1),
    .array([.string("a")]),
    .members(["k\u{FEFF}": .string("v\u{FEFF}")]),
    .object([]),
  ])
  func `a mark inside text, or no text at all, is not one`(value: AuthoredValue) {
    #expect(!value.hasTextStartingWithByteOrderMark)
  }
}
