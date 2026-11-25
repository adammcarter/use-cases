import Testing
@testable import UseCasesCore

struct StringYAMLNumberTests {
  @Test(arguments: ["0", "9x", "+1", "-1", ".5", "-.inf", "+.inf", "2024-01-01"])
  func `text that starts like a number is told apart`(text: String) {
    #expect(text.startsLikeANumber)
  }

  @Test(arguments: ["", "x", "on", "~", "<<", "=", "e3", "\u{663}", " 1", "i1"])
  func `text that starts any other way is not`(text: String) {
    #expect(!text.startsLikeANumber)
  }

  @Test(arguments: ["0", "7", "007", "1234567890", "99999999999999999999"])
  func `only digits are decimal digits`(text: String) {
    #expect(text.isDecimalDigits)
  }

  @Test(arguments: ["", "-1", "+1", "1.5", "1_0", "0x1", "1 ", "\u{663}", "1e3"])
  func `anything else is not`(text: String) {
    #expect(!text.isDecimalDigits)
  }
}
