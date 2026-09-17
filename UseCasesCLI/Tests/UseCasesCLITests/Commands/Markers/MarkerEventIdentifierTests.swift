import Foundation
import Testing
@testable import UseCasesCLI

/// `generateUlid`: JavaScript's base-32 time, upper-cased and padded to ten,
/// then sixteen random Crockford characters.
struct MarkerEventIdentifierTests {
  @Test(arguments: [
    (UInt64(0), "0000000000"),
    (UInt64(31), "000000000V"),
    (UInt64(32), "0000000010"),
    (UInt64(1_789_664_983_853), "01K2O5GUPD"),
  ])
  func `spells the time as toString(32) does`(
    milliseconds: UInt64,
    expected: String,
  ) {
    #expect(MarkerEventIdentifier.timePrefix(milliseconds: milliseconds) == expected)
  }

  @Test
  func `is twenty-six characters with a Crockford tail`() {
    let now = Date(timeIntervalSince1970: 1_789_664_983.8535)

    let identifier = MarkerEventIdentifier.generate(now: now)

    #expect(identifier.count == 26)
    #expect(identifier.hasPrefix("01K2O5GUPD"))
    #expect(identifier.dropFirst(10).allSatisfy { character in
      "0123456789ABCDEFGHJKMNPQRSTVWXYZ".contains(character)
    })
  }
}
