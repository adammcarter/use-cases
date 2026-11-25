import Testing
@testable import UseCasesCore

struct LinkRegionContributionOrderTests {
  @Test
  func `regions at one locator sort by content digest`() throws {
    let low = try FingerprintParts.region(file: "a.swift", start: 0, digestEnding: "01")
    let high = try FingerprintParts.region(file: "a.swift", start: 0, digestEnding: "ff")

    #expect(low.precedesByLocator(high))
    #expect(!high.precedesByLocator(low))
  }

  @Test
  func `a locator decides before the content does`() throws {
    let early = try FingerprintParts.region(file: "a.swift", start: 0, digestEnding: "ff")
    let late = try FingerprintParts.region(file: "a.swift", start: 1, digestEnding: "01")

    #expect(early.precedesByLocator(late))
    #expect(!late.precedesByLocator(early))
  }

  @Test
  func `identical regions precede neither way`() throws {
    let region = try FingerprintParts.region(file: "a.swift", start: 0)

    #expect(!region.precedesByLocator(region))
  }
}
