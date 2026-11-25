import Testing
@testable import UseCasesCore

struct ContentNormalizerTests {
  private func normalized(
    _ bytes: [UInt8],
    ignoring rules: [FreshnessNormalization],
  ) -> [UInt8] {
    ContentNormalizer(ignoring: rules).normalized(bytes)
  }

  @Test(
    arguments: [
      ("a\r\nb", "a\nb"),
      ("a\rb", "a\nb"),
      ("a\nb", "a\nb"),
      ("a\r\n\r\nb", "a\n\nb"),
      ("a\n\rb", "a\n\nb"),
      ("a\r\r\nb", "a\n\nb"),
      ("\r", "\n"),
      ("\r\n", "\n"),
      ("a\r\n", "a\n"),
      ("", ""),
      ("a \t b", "a \t b"),
    ],
  )
  func `line endings become LF and nothing else changes`(
    row: (text: String, expected: String),
  ) {
    let result = normalized(
      Array(row.text.utf8),
      ignoring: [.lineEndings],
    )

    #expect(result == Array(row.expected.utf8))
  }

  @Test
  func `exact mode keeps every byte`() {
    let bytes = Array("a\r\nb\rc \t\u{B}\u{C}\n".utf8)

    #expect(normalized(bytes, ignoring: []) == bytes)
  }

  @Test
  func `whitespace removes exactly TAB LF VT FF CR and SPACE`() {
    let bytes = Array("a\tb\nc\u{B}d\u{C}e\rf g".utf8)

    #expect(normalized(bytes, ignoring: [.whitespace]) == Array("abcdefg".utf8))
  }

  @Test(
    arguments: [
      "\u{A0}",
      "\u{2003}",
      "\u{3000}",
      "\u{2028}",
      "\u{85}",
      "\u{200B}",
      "\u{1C}",
    ],
  )
  func `other whitespace is not ignored`(character: String) {
    let bytes = Array("a\(character)b".utf8)

    #expect(normalized(bytes, ignoring: [.whitespace]) == bytes)
  }

  @Test
  func `line endings run before whitespace, so both together leave neither`() {
    let bytes = Array("a \r\n b\r".utf8)

    #expect(normalized(bytes, ignoring: [.lineEndings, .whitespace]) == Array("ab".utf8))
  }

  @Test
  func `the order and repetition of the rules do not matter`() {
    let bytes = Array("a \r\n b".utf8)

    let forward = normalized(bytes, ignoring: [.lineEndings, .whitespace])
    let backward = normalized(bytes, ignoring: [.whitespace, .lineEndings, .whitespace])

    #expect(forward == backward)
  }

  @Test
  func `a byte order mark is kept`() {
    let bytes = [0xEF, 0xBB, 0xBF] + Array("a\r\nb".utf8)

    let result = normalized(bytes, ignoring: [.lineEndings, .whitespace])

    #expect(result == [0xEF, 0xBB, 0xBF] + Array("ab".utf8))
  }

  @Test(
    arguments: [
      [0xFF, 0x0D, 0x0A],
      [0x61, 0x0D, 0x0A, 0xC3],
      [0xC0, 0xAF, 0x0D],
      [0xED, 0xA0, 0x80, 0x0D],
      [0xFF, 0xFE, 0x61, 0x00, 0x0D, 0x00],
    ] as [[UInt8]],
  )
  func `bytes that are not strict UTF-8 are hashed as they are`(bytes: [UInt8]) {
    let result = normalized(bytes, ignoring: [.lineEndings, .whitespace])

    #expect(result == bytes)
  }

  @Test
  func `multibyte text survives untouched`() {
    let bytes = Array("caf\u{E9}\r\n\u{65E5}\u{672C}\r\u{1F389}".utf8)

    let result = normalized(bytes, ignoring: [.lineEndings])

    #expect(result == Array("caf\u{E9}\n\u{65E5}\u{672C}\n\u{1F389}".utf8))
  }

  @Test
  func `a policy gives its rules`() {
    let policy = FreshnessPolicy(
      bindingIdentity: .content,
      ignoring: [.lineEndings],
    )

    let result = ContentNormalizer(policy: policy).normalized(Array("a\r\nb".utf8))

    #expect(result == Array("a\nb".utf8))
  }
}
