import Testing
@testable import UseCasesCore

struct RunIdentifierAllocatorTests {
  private static let clockNumber = "01a0d88fc5fbcdef0123456789abcdef"

  private func allocator(milliseconds: UInt64 = 1_790_339_696_123) -> RunIdentifierAllocator {
    RunIdentifierAllocator(
      clock: FixedTimekeeper(milliseconds: milliseconds),
      random: FixedRandomBits(),
    )
  }

  @Test
  func `a store with nothing in it gets the id the clock and the random bits make`() throws {
    let number = try allocator().next(above: nil)

    #expect(number.text == Self.clockNumber)
  }

  @Test
  func `the top 48 bits are the time in milliseconds`() throws {
    let number = try allocator().next(above: nil)

    #expect(number.high >> 16 == 1_790_339_696_123)
  }

  @Test
  func `an id above the clock's is kept when it is the greater`() throws {
    let highest = RunNumber(identifier: .sample(7))
    let number = try allocator().next(above: highest)

    #expect(number.text == Self.clockNumber)
  }

  @Test
  func `a clock that has gone back still allocates above the greatest id`() throws {
    let future =
      try RunNumber(identifier: RunIdentifier(validating: "ffff00000000000000000000000000ff"))
    let number = try allocator(milliseconds: 1).next(above: future)

    #expect(number == future.successor)
    #expect(number > future)
  }

  @Test
  func `the greatest id there is has nothing above it`() {
    let greatest = RunNumber(
      high: UInt64.max,
      low: UInt64.max,
    )

    #expect(throws: StoreWritingError.identifiersExhausted) {
      try allocator().next(above: greatest)
    }
  }
}
