extension LinkRegionContribution {
  /// The region a resolved link holds in `fileBytes`: its span is the locator, and the pieces
  /// of `contentRanges` joined are its content (chapter 11 §89.5).
  init(
    link: ResolvedLink,
    fileBytes: [UInt8],
    referencer: any ContentReferencing,
  ) throws(FingerprintingError) {
    guard link.span.lowerBound >= 0, link.span.upperBound <= fileBytes.count else {
      throw .regionOutsideFile(link.span)
    }

    try self.init(
      locator: FingerprintLocator(
        file: link.path,
        startByte: link.span.lowerBound,
        endByte: link.span.upperBound,
      ),
      content: referencer.reference(
        of: fileBytes,
        ranges: link.contentRanges,
      ),
    )
  }
}
