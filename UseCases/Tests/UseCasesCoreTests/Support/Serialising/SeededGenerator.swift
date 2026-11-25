/// A source of random numbers that gives the same numbers for the same seed, on every machine
/// (SplitMix64), so a failing case can be run again.
struct SeededGenerator: RandomNumberGenerator {
  private var state: UInt64

  init(seed: Int) {
    state = UInt64(truncatingIfNeeded: seed)
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15

    var mixed = state
    mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
    mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB

    return mixed ^ (mixed >> 31)
  }
}
