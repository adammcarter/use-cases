@testable import UseCasesCore

/// A random source that always gives the same bits.
struct FixedRandomBits: RandomBitsProviding {
  let value: UInt64

  init(value: UInt64 = 0x0123_4567_89AB_CDEF) {
    self.value = value
  }

  func next() -> UInt64 {
    value
  }
}
