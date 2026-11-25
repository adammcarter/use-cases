import Testing
@testable import UseCasesCore

struct ContentReferenceTests {
  private func reference(
    digest: String,
    length: Int,
  ) -> ContentReference {
    ContentReference(
      byteLength: length,
      digest: digest,
    )
  }

  @Test
  func `a reference writes exactly algorithm, byte length and digest`() throws {
    let value = reference(digest: String(repeating: "a", count: 64), length: 7).canonical

    #expect(
      try value.canonicalText()
        == "{\"algorithm\":\"sha256\",\"byte_length\":7,\"digest\":\""
        + String(repeating: "a", count: 64) + "\"}",
    )
  }

  @Test
  func `references sort by digest first`() {
    let low = reference(digest: "aa", length: 9)
    let high = reference(digest: "ab", length: 1)

    #expect(low.precedes(high))
    #expect(!high.precedes(low))
  }

  @Test
  func `equal digests sort by numeric length, not by text`() {
    let short = reference(digest: "aa", length: 9)
    let long = reference(digest: "aa", length: 10)

    #expect(short.precedes(long))
    #expect(!long.precedes(short))
  }

  @Test
  func `an identical reference precedes neither way`() {
    let one = reference(digest: "aa", length: 9)

    #expect(!one.precedes(one))
  }
}
