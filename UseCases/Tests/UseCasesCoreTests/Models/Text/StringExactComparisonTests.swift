import Testing
@testable import UseCasesCore

struct StringExactComparisonTests {
  private let composed = "caf\u{E9}"
  private let decomposed = "cafe\u{301}"

  @Test
  func `the same bytes are exactly equal`() {
    #expect(composed.isExactlyEqual(to: "caf\u{E9}"))
    #expect("".isExactlyEqual(to: ""))
  }

  @Test
  func `one name in two Unicode forms is not exactly equal`() {
    #expect(composed == decomposed)
    #expect(!composed.isExactlyEqual(to: decomposed))
  }

  @Test
  func `two Unicode forms hash apart`() {
    var composedHasher = Hasher()
    var decomposedHasher = Hasher()
    composed.hashExactly(into: &composedHasher)
    decomposed.hashExactly(into: &decomposedHasher)

    #expect(composedHasher.finalize() != decomposedHasher.finalize())
  }

  @Test(
    arguments: [
      ("a", "b"),
      ("a", "ab"),
      ("", "a"),
      ("ab", "b"),
    ],
  )
  func `a shorter or smaller text precedes`(
    smaller: String,
    larger: String,
  ) {
    #expect(smaller.precedesExactly(larger))
    #expect(!larger.precedesExactly(smaller))
    #expect(!smaller.precedesExactly(smaller))
  }

  @Test
  func `two Unicode forms are ordered one way or the other, never as equals`() {
    #expect(composed.precedesExactly(decomposed) != decomposed.precedesExactly(composed))
  }
}
