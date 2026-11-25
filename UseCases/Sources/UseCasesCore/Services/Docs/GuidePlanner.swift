/// Reads the words and flags of a search of the guides, and a `--next` token, as `search` reads
/// them.
public struct GuidePlanner: GuidePlanning {
  private let parser: any SearchQueryParsing
  private let codec: any SearchTokenCoding

  /// Makes the planner.
  public init() {
    self.init(
      parser: SearchQueryParser(),
      codec: SearchTokenCodec(),
    )
  }

  init(
    parser: any SearchQueryParsing,
    codec: any SearchTokenCoding,
  ) {
    self.parser = parser
    self.codec = codec
  }

  public func plan(
    words: String,
    isExact: Bool,
    pageSize: String?,
  ) throws(GuideSearchError) -> GuidePlan {
    let size: Int

    if let pageSize {
      guard let spelled = PageWindow.size(spelled: pageSize) else {
        throw .pageSize(pageSize)
      }

      size = spelled
    } else {
      size = PageWindow.defaultSize
    }

    let query: SearchQuery

    do {
      query = try parser.query(
        from: words,
        isExact: isExact,
      )
    } catch {
      throw .words(error)
    }

    return GuidePlan(
      query: query,
      pageSize: size,
      offset: 0,
      seal: nil,
    )
  }

  public func plan(continuing token: String) throws(GuideSearchError) -> GuidePlan {
    let plan: GuidePlan

    do {
      plan = try GuidePlan(
        reading: AuthoredObject(
          codec.parameters(in: token),
          at: "",
        ),
      )
    } catch {
      throw .invalidToken
    }

    // A token is read back only when it is exactly what a search writes, so an edit that changes
    // nothing a search reads is an edit all the same.
    guard
      let seal = plan.seal,
      codec.token(for: plan.document(sealedBy: seal)) == token,
      PageWindow.sizes.contains(plan.pageSize),
      plan.offset >= 0
    else {
      throw .invalidToken
    }

    return plan
  }
}
