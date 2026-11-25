import Testing
@testable import UseCasesCore

struct LinkRegionContributionTests {
  @Test
  func `a region reads its locator and content from a resolved link`() throws {
    let bytes = Array("0123456789".utf8)
    let link = try ResolvedLink.sample(
      file: "src/a.swift",
      span: 2 ..< 8,
    )
    let tagged = ResolvedLink(
      source: link.source,
      identity: link.identity,
      path: link.path,
      lines: link.lines,
      span: link.span,
      contentRanges: [2 ..< 4, 6 ..< 8],
    )
    let referencer = ContentReferencer(policy: .standard)

    let region = try LinkRegionContribution(
      link: tagged,
      fileBytes: bytes,
      referencer: referencer,
    )

    #expect(region.locator.file.text == "src/a.swift")
    #expect(region.locator.startByte == 2)
    #expect(region.locator.endByte == 8)
    #expect(region.content == referencer.reference(of: Array("2367".utf8)))
  }

  @Test
  func `a link whose span passes the end of the file is refused`() throws {
    let link = try ResolvedLink.sample(span: 0 ..< 10)

    #expect(throws: FingerprintingError.regionOutsideFile(0 ..< 10)) {
      try LinkRegionContribution(
        link: link,
        fileBytes: Array("short".utf8),
        referencer: ContentReferencer(policy: .standard),
      )
    }
  }
}
