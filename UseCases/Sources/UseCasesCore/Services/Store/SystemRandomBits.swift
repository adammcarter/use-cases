/// The system's random number generator.
struct SystemRandomBits: RandomBitsProviding {
  func next() -> UInt64 {
    UInt64.random(in: UInt64.min ... UInt64.max)
  }
}
