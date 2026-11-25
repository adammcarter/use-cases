import Testing
@testable import UseCasesCore

struct UInt8BlankTests {
  private static let blank: Set<UInt8> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20]

  @Test(arguments: Array(0 ... 255) as [Int])
  func `only TAB, LF, VT, FF, CR and SPACE are blank`(value: Int) {
    let byte = UInt8(value)

    #expect(byte.isBlankByte == Self.blank.contains(byte))
  }
}
