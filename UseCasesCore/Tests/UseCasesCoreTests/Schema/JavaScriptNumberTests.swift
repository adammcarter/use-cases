import Testing
@testable import UseCasesCore

/// Semantic hashes are taken over `JSON.stringify` output, so a number has to
/// be spelled the way JavaScript spells it — shortest round-trip digits, plain
/// notation up to 1e21, `e+`/`e-` beyond it, and `null` for anything not finite.
/// A single differing digit changes a hash that is written into ledgers.
struct JavaScriptNumberTests {
  @Test(arguments: [
    (0.0, "0"),
    (-0.0, "0"),
    (1.0, "1"),
    (-1.0, "-1"),
    (100.0, "100"),
    (1.5, "1.5"),
    (0.5, "0.5"),
    (-3.25, "-3.25"),
    (123.456, "123.456"),
    (0.1 + 0.2, "0.30000000000000004"),
    (1.0 / 3.0, "0.3333333333333333"),
    (9_007_199_254_740_992.0, "9007199254740992"),
    (1e20, "100000000000000000000"),
    (1e21, "1e+21"),
    (-1e21, "-1e+21"),
    (1e-6, "0.000001"),
    (1e-7, "1e-7"),
    (1e-21, "1e-21"),
    (5e-324, "5e-324"),
    (1.7976931348623157e308, "1.7976931348623157e+308"),
    (12_345_678_901_234_567_890.0, "12345678901234567000"),
  ])
  func `spells a finite number the way JavaScript does`(
    value: Double,
    expected: String,
  ) {
    #expect(JavaScriptNumber.text(value) == expected)
  }

  @Test(arguments: [Double.infinity, -.infinity, .nan])
  func `spells a non-finite number as null, the way JSON stringify does`(value: Double) {
    #expect(JavaScriptNumber.text(value) == "null")
  }

  @Test
  func `every spelling parses back to the same double`() throws {
    let values: [Double] = [0, 1, -1, 1.5, 0.1 + 0.2, 1e20, 1e-7, 5e-324, 1.7976931348623157e308]

    for value in values {
      let parsed = try #require(Double(JavaScriptNumber.text(value)))
      #expect(parsed == value)
    }
  }
}
