import Testing
@testable import UseCasesCore

struct ContentReferencerTests {
  private func referencer(_ rules: [FreshnessNormalization]) -> ContentReferencer {
    ContentReferencer(
      policy: FreshnessPolicy(
        bindingIdentity: .content,
        ignoring: rules,
      ),
    )
  }

  @Test
  func `empty content has the published empty reference`() {
    let reference = referencer([]).reference(of: [])

    #expect(reference.byteLength == 0)
    #expect(reference.digest == "e0de6ec0d583e251562c017f7084f22e1007c0f60276e00d18811909e976d4f5")
  }

  @Test
  func `the length counts normalized bytes, not framing`() {
    let reference = referencer([.lineEndings]).reference(of: Array("a\r\nb".utf8))

    #expect(reference.byteLength == 3)
  }

  @Test
  func `LF and CRLF checkouts agree under the default and differ when exact`() {
    let unix = Array("a\nb\n".utf8)
    let windows = Array("a\r\nb\r\n".utf8)

    let normalizing = referencer([.lineEndings])
    let exact = referencer([])

    #expect(normalizing.reference(of: unix) == normalizing.reference(of: windows))
    #expect(exact.reference(of: unix) != exact.reference(of: windows))
  }

  @Test
  func `a byte order mark changes the reference`() {
    let plain = referencer([.lineEndings]).reference(of: Array("a".utf8))
    let marked = referencer([.lineEndings]).reference(of: [0xEF, 0xBB, 0xBF] + Array("a".utf8))

    #expect(plain != marked)
    #expect(marked.byteLength == 4)
  }

  @Test
  func `pieces are joined in the order given before normalization`() throws {
    let bytes = Array("ab\rXXcd\n".utf8)

    let pieces = try referencer([.lineEndings]).reference(
      of: bytes,
      ranges: [0 ..< 3, 5 ..< 8],
    )
    let whole = referencer([.lineEndings]).reference(of: Array("ab\rcd\n".utf8))

    #expect(pieces == whole)
  }

  @Test
  func `a CR ending one piece and an LF starting the next make one line ending`(
  ) throws {
    let bytes = Array("a\rXX\nb".utf8)

    let pieces = try referencer([.lineEndings]).reference(
      of: bytes,
      ranges: [0 ..< 2, 4 ..< 6],
    )

    #expect(pieces.byteLength == 3)
  }

  @Test(arguments: [-1 ..< 2, 0 ..< 9, 4 ..< 9])
  func `a range outside the bytes is refused`(range: Range<Int>) {
    #expect(throws: FingerprintingError.regionOutsideFile(range)) {
      try referencer([]).reference(
        of: Array("abcd".utf8),
        ranges: [range],
      )
    }
  }

  @Test
  func `no ranges is the empty reference`() throws {
    let reference = try referencer([]).reference(
      of: Array("abc".utf8),
      ranges: [],
    )

    #expect(reference == referencer([]).reference(of: []))
  }
}
