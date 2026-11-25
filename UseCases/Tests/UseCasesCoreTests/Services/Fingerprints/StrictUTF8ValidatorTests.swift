import Testing
@testable import UseCasesCore

struct StrictUTF8ValidatorTests {
  /// Bytes in the places where text goes wrong: leading bytes, the bytes that follow them, and
  /// the bytes that are never allowed.
  private static let pool: [UInt8] = [
    0x41, 0x0A, 0xC3, 0xA9, 0xE2, 0x82, 0xAC, 0xF0, 0x9F, 0x98, 0x80, 0x80, 0xC0, 0xED, 0xA0, 0xFF,
    0xF4, 0x90, 0xC2, 0xBF,
  ]

  private func verdict(of chunks: [[UInt8]]) -> Bool {
    var validator = StrictUTF8Validator()

    for chunk in chunks {
      validator.add(chunk)
    }

    return validator.isStrictUTF8
  }

  private func splits(of bytes: [UInt8]) -> [[[UInt8]]] {
    (0 ... bytes.count).map { first in
      [Array(bytes[..<first]), Array(bytes[first...])]
    }
  }

  @Test(arguments: [
    Array("plain text".utf8),
    Array("é€😀 mixed".utf8),
    [],
    [0xC3, 0xA9],
    [0xE2, 0x82, 0xAC],
    [0xF0, 0x9F, 0x98, 0x80],
  ] as [[UInt8]])
  func `text is text wherever it is cut`(bytes: [UInt8]) {
    for chunks in splits(of: bytes) {
      #expect(verdict(of: chunks))
    }
  }

  @Test(arguments: [
    [0xC0, 0x80],
    [0x80],
    [0xED, 0xA0, 0x80],
    [0xE2, 0x82],
    [0xF4, 0x90, 0x80, 0x80],
    [0xFF],
    [0x41, 0xC3],
    [0xF0, 0x9F, 0x98],
  ] as [[UInt8]])
  func `what is not text is not text wherever it is cut`(bytes: [UInt8]) {
    for chunks in splits(of: bytes) {
      #expect(!verdict(of: chunks))
    }
  }

  @Test
  func `chunks cut in every place give the answer for all the bytes at once`() {
    var state: UInt32 = 12345

    for _ in 0 ..< 3000 {
      state = state &* 1_664_525 &+ 1_013_904_223
      let count = Int(state >> 28) + 1
      let bytes = (0 ..< count).map { _ -> UInt8 in
        state = state &* 1_664_525 &+ 1_013_904_223

        return Self.pool[Int(state >> 16) % Self.pool.count]
      }

      for chunks in splits(of: bytes) {
        #expect(verdict(of: chunks) == bytes.isStrictUTF8, "bytes \(bytes) cut as \(chunks)")
      }
    }
  }

  @Test
  func `a sequence cut over three chunks is still one character`() {
    #expect(verdict(of: [[0xF0], [0x9F], [0x98], [0x80]]))
    #expect(!verdict(of: [[0xF0], [0x9F], [0x98]]))
  }

  @Test
  func `once it is not text it stays so`() {
    var validator = StrictUTF8Validator()
    validator.add([0xFF])
    validator.add(Array("fine".utf8))

    #expect(!validator.isStrictUTF8)
  }
}
