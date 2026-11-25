/// Allocates `max(last + 1, milliseconds since 1970 << 80 | 80 random bits)` (chapter 12 §8).
struct RunIdentifierAllocator: RunIdentifierAllocating {
  private let clock: any Timekeeping
  private let random: any RandomBitsProviding

  init(
    clock: any Timekeeping = SystemTimekeeper(),
    random: any RandomBitsProviding = SystemRandomBits(),
  ) {
    self.clock = clock
    self.random = random
  }

  func next(above highest: RunNumber?) throws(StoreWritingError) -> RunNumber {
    let candidate = RunNumber(
      milliseconds: clock.now().storeMilliseconds,
      randomHigh: UInt16(truncatingIfNeeded: random.next()),
      randomLow: random.next(),
    )

    guard let highest else {
      return candidate
    }
    guard let floor = highest.successor else {
      throw .identifiersExhausted
    }

    return max(
      candidate,
      floor,
    )
  }
}
