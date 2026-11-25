import Testing
@testable import UseCasesCore

struct YAMLIntegerTests {
  @Test(arguments: [
    ("0", 10, false, YAMLInteger.exact(0)),
    ("0000", 10, false, .exact(0)),
    ("7", 10, false, .exact(7)),
    ("007", 10, false, .exact(7)),
    ("7", 10, true, .exact(-7)),
    ("1_000", 10, false, .exact(1000)),
    ("17", 8, false, .exact(15)),
    ("1F", 16, false, .exact(31)),
    ("101", 2, false, .exact(5)),
    ("9223372036854775807", 10, false, .exact(Int.max)),
    ("9223372036854775808", 10, false, .tooLarge),
    ("9223372036854775808", 10, true, .exact(Int.min)),
    ("9223372036854775809", 10, true, .tooLarge),
    ("7FFFFFFFFFFFFFFF", 16, false, .exact(Int.max)),
    ("8000000000000000", 16, false, .tooLarge),
    ("00000000000000000000000000007", 10, false, .exact(7)),
    ("99999999999999999999999999999", 10, false, .tooLarge),
  ])
  func `digits are read in their radix and never rounded`(
    digits: String,
    radix: Int,
    isNegative: Bool,
    expected: YAMLInteger,
  ) {
    let integer = YAMLInteger(
      digits: Substring(digits),
      radix: radix,
      isNegative: isNegative,
    )

    #expect(integer == expected)
  }
}
