import Testing
@testable import UseCasesCore

struct TerminalControlTests {
  @Test(arguments: [
    (UInt32(0x0), "\\x00"),
    (0x7, "\\x07"),
    (0x1B, "\\x1B"),
    (0x1F, "\\x1F"),
    (0x7F, "\\x7F"),
    (0x80, "\\x80"),
    (0x9B, "\\x9B"),
    (0x9F, "\\x9F"),
    (0x202A, "\\u202A"),
    (0x202E, "\\u202E"),
    (0x2066, "\\u2066"),
    (0x2069, "\\u2069"),
  ])
  func `a character a terminal would act on is spelled out`(
    value: UInt32,
    spelled: String,
  ) throws {
    let scalar = try #require(Unicode.Scalar(value))

    #expect(scalar.isTerminalControl)
    #expect(scalar.escapedForDisplay == spelled)
  }

  @Test(arguments: [
    UInt32(0x20), 0x21, 0x41, 0x7E, 0xA0, 0xE9, 0x2029, 0x202F, 0x2065, 0x206A, 0x1F600,
    0x9, 0xA, 0xD, 0xB, 0xC, 0x85, 0x2028,
  ])
  func `any other character is itself, and white space is left to be collapsed`(
    value: UInt32,
  ) throws {
    let scalar = try #require(Unicode.Scalar(value))

    #expect(!scalar.isTerminalControl)
    #expect(scalar.escapedForDisplay == String(scalar))
  }

  @Test
  func `a text has every control spelled out and the rest kept`() {
    #expect("a\u{1B}[8mb\u{202E}c é".displayEscaped == "a\\x1B[8mb\\u202Ec é")
    #expect("plain".displayEscaped == "plain")
    #expect("".displayEscaped.isEmpty)
    #expect("a\u{1B}b".firstTerminalControl == "\u{1B}")
    #expect("abc".firstTerminalControl == nil)
  }
}
