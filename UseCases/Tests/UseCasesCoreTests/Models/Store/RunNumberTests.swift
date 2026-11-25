import Testing
@testable import UseCasesCore

struct RunNumberTests {
  @Test
  func `a run id and its number are the same thing`() {
    let identifier = RunIdentifier.sample(42)
    let number = RunNumber(identifier: identifier)

    #expect(number.high == 0)
    #expect(number.low == 42)
    #expect(number.text == identifier.text)
  }

  @Test(arguments: [
    "01a0d88fc5fbcdef0123456789abcdef",
    "ffffffffffffffffffffffffffffffff",
    "00000000000000010000000000000000",
    "0000000000000000ffffffffffffffff",
  ])
  func `a full width id survives the trip through its number`(text: String) throws {
    let identifier = try RunIdentifier(validating: text)

    #expect(try RunNumber(identifier: identifier).identifier() == identifier)
    #expect(RunNumber(identifier: identifier).text == text)
  }

  @Test
  func `the time is the top 48 bits and the random bits are the 80 below`() {
    let number = RunNumber(
      milliseconds: 1_790_339_696_123,
      randomHigh: 0xCDEF,
      randomLow: 0x0123_4567_89AB_CDEF,
    )

    #expect(number.text == "01a0d88fc5fbcdef0123456789abcdef")
  }

  @Test
  func `milliseconds past 48 bits keep only the low 48`() {
    let number = RunNumber(
      milliseconds: 0x1_0000_0000_0001,
      randomHigh: 0,
      randomLow: 0,
    )

    #expect(number.text == "00000000000100000000000000000000")
  }

  @Test
  func `the successor is one more`() {
    let number = RunNumber(
      high: 5,
      low: 9,
    )

    #expect(number.successor == RunNumber(high: 5, low: 10))
  }

  @Test
  func `the successor of a full low half carries into the high half`() {
    let number = RunNumber(
      high: 5,
      low: UInt64.max,
    )

    #expect(number.successor == RunNumber(high: 6, low: 0))
  }

  @Test
  func `nothing is above the greatest number`() {
    let greatest = RunNumber(
      high: UInt64.max,
      low: UInt64.max,
    )

    #expect(greatest.successor == nil)
  }

  @Test
  func `the high half decides before the low half`() {
    let small = RunNumber(high: 1, low: UInt64.max)
    let large = RunNumber(high: 2, low: 0)

    #expect(small < large)
    #expect(!(large < small))
    #expect(RunNumber(high: 2, low: 1) > large)
  }

  @Test
  func `numbers order as the text of their ids does`() {
    let numbers = [
      RunNumber(high: 1, low: 0),
      RunNumber(high: 0, low: UInt64.max),
      RunNumber(high: 0, low: 1),
    ].sorted()

    #expect(numbers.map(\.text) == numbers.map(\.text).sorted())
  }

  @Test
  func `zero is not a run id`() {
    #expect(throws: RunIdentifierError.reserved) {
      try RunNumber(high: 0, low: 0).identifier()
    }
  }
}
