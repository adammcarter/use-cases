import Testing
@testable import UseCasesCore

struct CanonicalJSONEncoderTests {
  private func text(_ value: CanonicalValue) throws -> String {
    try value.canonicalText()
  }

  @Test
  func `the escaping probe of the chapter encodes to its published bytes`() throws {
    let value = CanonicalValue.members([
      "z": .string("\n\"\\"),
      "a": .string("\u{E9}"),
    ])

    #expect(try text(value) == #"{"a":"é","z":"\u000a\"\\"}"#)
  }

  @Test
  func `null booleans and zero are lowercase and plain`() throws {
    let value = CanonicalValue.array([.null, .boolean(true), .boolean(false), .integer(0)])

    #expect(try text(value) == "[null,true,false,0]")
  }

  @Test(
    arguments: [
      (1, "1"),
      (-1, "-1"),
      (9_007_199_254_740_991, "9007199254740991"),
      (-9_007_199_254_740_991, "-9007199254740991"),
    ],
  )
  func `integers are base 10 with no sign but a minus`(
    number: Int,
    expected: String,
  ) throws {
    #expect(try text(.integer(number)) == expected)
  }

  @Test(arguments: [9_007_199_254_740_992, -9_007_199_254_740_992, Int.max, Int.min])
  func `an integer beyond 2^53 - 1 is refused`(number: Int) {
    #expect(throws: CanonicalEncodingError.integerOutOfRange(number)) {
      try CanonicalJSONEncoder().encode(.integer(number))
    }
  }

  @Test(arguments: Array(0 ..< 0x20))
  func `every control character is a six byte lowercase escape`(code: Int) throws {
    let scalar = Unicode.Scalar(UInt8(code))
    let hex = String(code, radix: 16)
    let expected = "\"\\u" + String(repeating: "0", count: 4 - hex.count) + hex + "\""

    #expect(try text(.string(String(scalar))) == expected)
  }

  @Test
  func `no short escape stands in for newline tab backspace form feed or return`() throws {
    let value = CanonicalValue.string("\n\t\u{8}\u{C}\r")

    #expect(try text(value) == #""\u000a\u0009\u0008\u000c\u000d""#)
  }

  @Test(
    arguments: [
      "/",
      "\u{7F}",
      "\u{80}",
      "\u{2028}",
      "\u{2029}",
      "\u{E9}",
      "\u{65E5}\u{672C}",
      "\u{1F389}",
      "\u{FEFF}",
      "\u{FFFD}",
    ],
  )
  func `every other scalar is written as it is`(character: String) throws {
    let bytes = try CanonicalJSONEncoder().encode(.string(character))

    #expect(bytes == Array("\"".utf8) + Array(character.utf8) + Array("\"".utf8))
  }

  @Test
  func `a quotation mark and a backslash are escaped with a backslash`() throws {
    #expect(try text(.string("a\"b\\c")) == #""a\"b\\c""#)
  }

  @Test
  func `strings are never normalized`() throws {
    let composed = "caf\u{E9}"
    let decomposed = "cafe\u{301}"

    let composedBytes = try CanonicalJSONEncoder().encode(.string(composed))
    let decomposedBytes = try CanonicalJSONEncoder().encode(.string(decomposed))

    #expect(composedBytes == Array("\"caf\u{E9}\"".utf8))
    #expect(decomposedBytes == Array("\"cafe\u{301}\"".utf8))
    #expect(composedBytes != decomposedBytes)
  }

  @Test
  func `keys sort by UTF-8 bytes`() throws {
    let value = CanonicalValue.members([
      "b": .integer(1),
      "a": .integer(2),
      "B": .integer(3),
      "_": .integer(4),
      "\u{E9}": .integer(5),
      "z": .integer(6),
    ])

    #expect(try text(value) == #"{"B":3,"_":4,"a":2,"b":1,"z":6,"é":5}"#)
  }

  @Test
  func `a supplementary key follows a fullwidth one by bytes, not by UTF-16`() throws {
    let emoji = "\u{1F389}"
    let fullwidth = "\u{FF5E}"
    let value = CanonicalValue.members([
      emoji: .integer(1),
      fullwidth: .integer(2),
    ])

    let expected = "{\"" + fullwidth + "\":2,\"" + emoji + "\":1}"

    #expect(try text(value) == expected)
  }

  @Test
  func `a shorter key sorts before a longer one it begins`() throws {
    let value = CanonicalValue.members([
      "ab": .integer(1),
      "a": .integer(2),
    ])

    #expect(try text(value) == #"{"a":2,"ab":1}"#)
  }

  @Test
  func `the order members are given in does not change the bytes`() throws {
    let forward = CanonicalValue.members(["x": .integer(1), "y": .integer(2), "z": .integer(3)])
    let backward = CanonicalValue.members(["z": .integer(3), "y": .integer(2), "x": .integer(1)])

    #expect(try text(forward) == text(backward))
  }

  @Test
  func `array order is kept`() throws {
    let value = CanonicalValue.strings(["b", "a", "c"])

    #expect(try text(value) == #"["b","a","c"]"#)
  }

  @Test
  func `nesting writes no whitespace`() throws {
    let value = CanonicalValue.members([
      "k": .array([.members(["a": .null]), .array([])]),
      "e": .members([:]),
    ])

    #expect(try text(value) == #"{"e":{},"k":[{"a":null},[]]}"#)
  }

  @Test
  func `a repeated key is refused`() {
    let value = CanonicalValue.object([
      CanonicalMember(key: "a", value: .integer(1)),
      CanonicalMember(key: "a", value: .integer(2)),
    ])

    #expect(throws: CanonicalEncodingError.duplicateKey("a")) {
      try CanonicalJSONEncoder().encode(value)
    }
  }

  @Test
  func `the same key in two Unicode forms is two keys`() throws {
    let value = CanonicalValue.object([
      CanonicalMember(key: "caf\u{E9}", value: .integer(1)),
      CanonicalMember(key: "cafe\u{301}", value: .integer(2)),
    ])

    #expect(try text(value) == "{\"cafe\u{301}\":2,\"caf\u{E9}\":1}")
  }

  @Test
  func `a repeated key inside a nested object is refused`() {
    let value = CanonicalValue.array([
      .object([
        CanonicalMember(key: "k", value: .null),
        CanonicalMember(key: "k", value: .null),
      ]),
    ])

    #expect(throws: CanonicalEncodingError.duplicateKey("k")) {
      try CanonicalJSONEncoder().encode(value)
    }
  }
}
