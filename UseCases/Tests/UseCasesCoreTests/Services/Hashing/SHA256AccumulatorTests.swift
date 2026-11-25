import Testing
@testable import UseCasesCore

struct SHA256AccumulatorTests {
  private let hasher = SHA256Hasher()

  @Test
  func `nothing added is the published digest of nothing`() {
    #expect(
      SHA256Accumulator()
        .hex() == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    )
  }

  @Test
  func `abc is the published digest of abc, added in one piece or three`() {
    var whole = SHA256Accumulator()
    var pieces = SHA256Accumulator()
    whole.add(Array("abc".utf8))
    pieces.add(Array("a".utf8))
    pieces.add([])
    pieces.add(Array("bc".utf8))

    let published = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    #expect(whole.hex() == published)
    #expect(pieces.hex() == published)
  }

  @Test(arguments: ChunkSamples.sizes)
  func `bytes added in chunks give the digest of the bytes at once`(size: Int) {
    let bytes = ChunkSamples.bytes(count: size)
    var accumulator = SHA256Accumulator()

    for start in stride(from: 0, to: bytes.count, by: 65536) {
      accumulator.add(Array(bytes[start ..< min(start + 65536, bytes.count)]))
    }

    #expect(accumulator.hex() == hasher.sha256Hex(of: bytes))
  }

  @Test
  func `the digest so far can be asked for and the adding goes on`() {
    var accumulator = SHA256Accumulator()
    accumulator.add(Array("ab".utf8))
    let early = accumulator.hex()
    accumulator.add(Array("c".utf8))

    #expect(early == hasher.sha256Hex(of: Array("ab".utf8)))
    #expect(accumulator.hex() == hasher.sha256Hex(of: Array("abc".utf8)))
  }

  @Test
  func `a hasher gives accumulators that do not share what they were given`() {
    var first = hasher.accumulator()
    let second = hasher.accumulator()
    first.add([1])

    #expect(second.hex() == hasher.sha256Hex(of: []))
  }
}
