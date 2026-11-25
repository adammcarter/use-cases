import Testing
@testable import UseCasesCore

struct FingerprintLocatorTests {
  private func locator(
    _ file: String,
    _ start: Int,
    _ end: Int,
  ) throws -> FingerprintLocator {
    try FingerprintLocator(
      file: workspacePath(file),
      startByte: start,
      endByte: end,
    )
  }

  @Test
  func `a locator writes exactly file, start byte and end byte`() throws {
    let value = try locator("src/a.swift", 3, 9).canonical

    #expect(try value.canonicalText() == #"{"end_byte":9,"file":"src/a.swift","start_byte":3}"#)
  }

  struct Place {
    let file: String
    let start: Int
    let end: Int
  }

  private static let orderedPairs = [
    (Place(file: "a", start: 9, end: 9), Place(file: "b", start: 0, end: 0)),
    (Place(file: "a", start: 1, end: 9), Place(file: "a", start: 2, end: 3)),
    (Place(file: "a", start: 1, end: 2), Place(file: "a", start: 1, end: 3)),
    (Place(file: "a", start: 9, end: 10), Place(file: "a", start: 10, end: 11)),
    (Place(file: "A", start: 0, end: 0), Place(file: "a", start: 0, end: 0)),
  ]

  @Test(arguments: orderedPairs)
  func `locators sort by file, then start, then end, numerically`(
    pair: (earlier: Place, later: Place),
  ) throws {
    let earlier = try locator(pair.earlier.file, pair.earlier.start, pair.earlier.end)
    let later = try locator(pair.later.file, pair.later.start, pair.later.end)

    #expect(earlier.precedes(later))
    #expect(!later.precedes(earlier))
  }

  @Test
  func `file names sort by bytes, so a decomposed name precedes a composed one`() throws {
    let composed = try locator("caf\u{E9}", 0, 0)
    let decomposed = try locator("cafe\u{301}", 0, 0)

    #expect(decomposed.precedes(composed))
    #expect(composed != decomposed)
  }
}
