import Testing
@testable import UseCasesCore

struct ArrayLossyTextTests {
  @Test(
    arguments: [
      ([], ""),
      ([0x61, 0x62], "ab"),
      ([0xC3, 0xA9], "\u{E9}"),
      ([0xF0, 0x9F, 0x98, 0x80], "\u{1F600}"),
      ([0xFF], "\u{FFFD}"),
      ([0x61, 0xFF, 0x62], "a\u{FFFD}b"),
      ([0xC3], "\u{FFFD}"),
      ([0xA9, 0x61], "\u{FFFD}a"),
      ([0xE2, 0x82], "\u{FFFD}"),
    ] as [([UInt8], String)],
  )
  func `invalid sequences become U+FFFD and valid text is kept`(
    bytes: [UInt8],
    text: String,
  ) {
    #expect(bytes.lossyUTF8Text == text)
  }
}
